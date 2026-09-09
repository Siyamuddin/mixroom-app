# Targeted pitch repair — local integration

Status: local-only, default off. No production activation, deployment, commit,
push, or PR update. No live model requests during this integration step.

## Scope and safety

The previously evaluated pitch-patch implementation now lives in
`backend/llm_proxy/src/common/v3_pitch_repair.py`. The evaluation module re-exports
it so evaluation and handler execution use the same implementation. Its compact
request, strict patch schema and reconstructed-plan checks are unchanged; the
deterministic comparison report remained byte-identical after the move.

The real handler can select it only through a trusted local Python context
attribute, set by the bridge's explicit `--targeted-pitch-repair` flag. It is not
an environment flag, request field, header, client capability or deployment
setting. Ordinary Lambda contexts and bridges without the flag retain the
existing path. Frozen contract 3 remains excluded even with local opt-in.

Only structurally valid plans with eligible unsupported pitches qualify. Other
semantic failures, uncertain bounds and ambiguous downstream dependencies remain
ineligible and use the existing repair behavior. An eligible patch replaces the
single full-plan repair attempt; a failed patch never triggers another repair.
Analysis time consumes the same shared deadline. Successful first-pass plans
still make one provider request; repaired requests make at most two.

Only the identified unsupported pitch fields may change. Reconstructed plans
pass normal semantic validation before being returned to the app. Valid notes,
timing, velocities, commands, instruments, section count and reply are preserved.
There is no application-side pitch clamping or musical fallback. The ordinary
app validator, executor, verification and undo paths remain unchanged.

New selection/result counters stay in the final backend log and local bridge
health response. Raw plans and patches remain in memory. Public errors,
responses, analytics and persisted usage retain their existing shape; the tool
identity stays `submit_plan_v3`, with actual provider usage handled as before.
No repair instructions or repair implementation were added to app source/assets.

## Verification

Final local results: **321 backend tests, 237 selected client tests, and the
native macOS acceptance test passed**. `git diff --check` passed. No Python
bytecode artifacts were generated under the backend/evaluation directories.
The native four-request fixture recorded eight provider attempts: three accepted
patches finalized usage and one invalid patch released usage with no project
change. Build-generated dependency-lock changes were removed.

- Seven real-handler integration tests, with HTTP and REST subcases: raw rejected
  plans and raw patches, reconstruction, default-off/request injection guard,
  successful first pass, ineligible fallback, malformed/refused/incomplete
  patches, provider timeout, exhausted shared deadline, settlement and legacy
  compatibility.
- Existing deterministic prototype tests and profiler hashes remain regression
  gates. No first-pass instructions, provider settings or profile baselines were
  changed in this integration step.
- Native test: `integration_test/ai_v3_pitch_repair_local_test.dart`, backed by
  `pitch_repair_local_fixture.py`, uses a new temporary synthetic project and
  only a loopback fake provider. It checks creation of two eight-bar sections,
  replacement, append, exact note/timing readback, undo/redo, save/reopen, and an
  invalid patch leaving the project and undo history unchanged.

The native fixture is intentionally four requests per server instance. Restart
that fixture bridge before rerunning the test. It does not use project #132 or
the manual live bridge. Its mocked pitches are test data, not runtime logic.

From the worktree root, start the fixture in a separate terminal:

```sh
PYTHONDONTWRITEBYTECODE=1 python tool/ai_v3_eval/pitch_repair_local_fixture.py --port 8768 --targeted-pitch-repair
```

Then run the isolated native test:

```sh
flutter test integration_test/ai_v3_pitch_repair_local_test.dart -d macos --no-pub \
  --dart-define=AI_V3_PITCH_REPAIR_LOCAL_TEST=true \
  --dart-define=AI_V3_PRIMARY_ENABLED=true \
  --dart-define=AI_V3_RESOURCE_REFS_ENABLED=true \
  --dart-define=AI_V3_LONG_PATH_ENABLED=true \
  --dart-define=AI_V3_LONG_API_BASE_URL=http://127.0.0.1:8768 \
  --dart-define=LLM_PROXY_API_BASE_URL=http://127.0.0.1:8768 \
  --dart-define=APP_API_BASE_URL=http://127.0.0.1:8768 \
  --dart-define=SUBSCRIPTION_API_BASE_URL=http://127.0.0.1:8768
```

Stop only the fixture bridge after the test. Generated project data stays in its
temporary directory. The test allows newly allocated placeholder render paths
on reopen: live MIDI loads notes directly into the engine and need not create a
WAV. Every other clip snapshot field (including notes, timing, trim and identity)
must match exactly. This is state/readback coverage, not an audio-quality test.

## Remaining limitations

These deterministic tests establish integration and safety, not musical quality
or provider latency. The earlier bounded live comparison was small: 11/12
full-plan repairs and 12/12 targeted repairs passed backend validation; targeted
repair was faster in all 12 paired trials. That is encouraging evidence, not a
guarantee against model mistakes or all timeouts.

No deployment switch has been added. Any production adoption requires a separate
review and explicit deployment approval after merge. Existing released clients
have not been changed by this local work.
