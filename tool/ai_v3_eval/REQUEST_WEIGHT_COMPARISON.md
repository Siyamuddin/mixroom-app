# Fixed five-part request-weight comparison

Evaluation only: `compare_request_weight.py` is not imported by the handler,
bridge, or app. No runtime behavior, prompt, model, deadline or validation change.

## Question and isolation

Does sharing repeated, identical enum definitions materially improve first-pass
latency for a five-part MIDI rewrite without worsening contract validity?

The candidate replaces duplicated enum subschemas with local `$defs`/`$ref`
references. Expanding them must reproduce the complete original provider request
exactly. Enum members/order, descriptions, commands, context, instructions,
output shape and model settings are preserved. This does not remove resource
identifiers or narrow the model's choices. Definitions are supported by
[OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs#definitions-are-supported).

The reconstructed synthetic fixture has piano, drums, bass and two guitar clips,
four instrument rows plus an empty row, 320 existing notes, 135 synthetic library
assets, eight conversation turns and all 54 command types. It is not the original
project #132 and has a smaller payload than the observed manual requests.

Canonical request: 157,805 → 134,631 bytes (14.7% reduction).
Canonical tool parameters: 107,090 → 83,916 bytes (21.6% reduction).
Actual serialized upstream request: 165,313 → 141,276 bytes.
Fourteen exact shared definitions; no baseline files changed.

## Protocol

- Six baseline and six candidate requests, sequentially interleaved; pair order
  alternates. The first pair is labelled, not silently discarded or warmed up.
- Same existing local provider adapter, gpt-5.6-luna, low reasoning, 8,192 output
  token budget, 24-hour prompt-cache retention and 55-second provider deadline.
- No repair, resubmission, production Mixroom request, app execution or project
  mutation. Provider usage is billable. The manual bridge is left untouched.
- Fixed state/history on every trial. Actual cache usage is reported; cache
  hit/miss and new-schema processing can confound comparisons in this small run.
- Backend validation followed by the real Dart client contract parser. Scope
  scoring requires one nonempty, changed note replacement per existing clip,
  with no other operations. Thus instruments/positions cannot be changed by an
  accepted fixture plan. This is a conservative evaluation gate, not a new
  product restriction, and it is not musical-quality or full native execution
  verification. Language is not independently graded by this harness.
- Generated plans remain in memory and pass to the Dart checker through stdin;
  only safe numeric/category results are written outside the repository.
- HTTP round-trip and backend-validation timing are recorded. Non-streaming
  requests cannot separate model queueing, input processing and generation;
  output-token counts do not turn round-trip time into a true decode-speed
  measurement. Timeouts are censored observations, not completed 55-second runs.

OpenAI notes that output generation commonly dominates latency and reducing
inputs can have a smaller effect. This run measures rather than assumes an
input-size benefit. See [latency optimization](https://developers.openai.com/api/docs/guides/latency-optimization).

## Reproduction

Offline equivalence/profile only:

```sh
PYTHONDONTWRITEBYTECODE=1 python tool/ai_v3_eval/compare_request_weight.py --output /tmp/pro4-request-weight-comparison.json
```

The explicit `--execute-live` flag runs exactly twelve provider calls. The
existing configured provider credential must be available; never print it.
`--dart` can select the installed Dart SDK. The output path must be outside the
repository. There is no adoption switch or automatic code mutation.

Raw plans are not retained, and the harness must not claim recovery of the
historical client rejection unless a new matching case is actually observed.
Six trials per arm are exploratory, not a production reliability estimate.

## Results — 2026-09-08 local run

Exactly twelve live requests completed; no repairs or retries were made.
**Do not adopt the schema candidate.** Both variants achieved two complete
backend/client/scope successes. The candidate had more observed timeouts.

| Result | Current request | Shared enum candidate |
| --- | ---: | ---: |
| Trials | 6 | 6 |
| Contract + scope successes | 2 | 2 |
| Provider timeouts | 2 | 4 |
| Backend accepted, client rejected | 2 | 0 |
| Completed-call median provider time | 51.65 s | 39.01 s |
| Completed-call generated notes | 240–283 | 160–192 |
| Reported input tokens on each completion | 34,996 | 34,996 |

Completed calls in both variants reported 34,865 cached input tokens. The
candidate's lower completed-call median is not evidence of a reliability gain:
it excludes four timeouts and its completed outputs contained fewer notes.
Request bytes fell, but reported input-token count did not. The run does not
establish the provider's internal handling of shared definitions.

No newly completed request needed more than 75 ms for backend validation.
Provider work dominates observed duration; non-streaming measurements still
cannot attribute queueing versus input processing versus generation.

### Concrete compatibility defect discovered

Two baseline responses contained 264 and 283 generated notes. Both passed backend
validation, but the real client parser rejected them with
`v3_generated_midi_limit`. The client enforces 256 generated notes across create,
replace and append commands in one plan; the tested backend accepted these
over-budget plans. This recreates the earlier symptom, but the historical full
plan was not retained, so its exact attribution remains unproven.

`check_note_limit.py` independently reproduces the boundary with synthetic plans
and **zero model calls**:

| Total generated notes | Backend | Client |
| --- | --- | --- |
| 256 | Accept | Accept |
| 257 | Accept | Reject: `v3_generated_midi_limit` |
| 264 | Accept | Reject: `v3_generated_midi_limit` |

Next priority: reconcile the existing aggregate generated-note contract between
backend and client, including how that budget is communicated to generation.
Do not truncate notes, widen old-client limits, or claim that this alone will
eliminate provider timeouts. No validation fix was implemented in this measurement
step. The candidate stays evaluation-only and is not imported by runtime code.

Verification: 326 backend tests passed, including five new harness tests;
the Dart checker and offline boundary reproduction ran successfully;
`git diff --check` passed, and no Python bytecode artifacts were generated.
Detailed safe results: `/tmp/pro4-request-weight-comparison.json`.
