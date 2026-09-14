# Pitch presentation experiment

Predeclared experiment, 2026-09-07. Evaluation-only; not imported by the backend.

Hypothesis: a compact, derived instrument-range summary beside the original
request improves first-pass playable-note generation. The normal context,
instructions, model, schema, deadlines, and repair behavior are unchanged.
The first-pass runner bypasses repair. No app/project writes, production-log
queries, or production mutations. The existing configured provider-key lookup
is reused for the explicitly enabled live synthetic calls.

Five scenarios, four repetitions per variant (20 baseline + 20 candidate),
interleaved with concurrency two: exact clarification follow-up, low-register
guitar, range-limited flute, sparse synthetic drums, ordered instrument switching.
Each has a synthetic 135-instrument catalog. The sparse drum fixture represents
advertised post-remapping intervals, not an actual native instrument remap.
These are controlled synthetic requests, not a captured #132 request.

Use the existing model and settings: gpt-5.6-luna, low reasoning, 8192 maximum
output tokens, 55-second deadline. No retries. Raw synthetic outputs stay in /tmp.

Adoption gates, set before calls: at least two more first-pass successes than
baseline, at least 18/20 overall, fewer pitch violations, and no increase in
observed scope, instrument, language, or other-invalid-output failures.
Unnecessary clarification is a failed scope result for these feasible scenarios.
Code grades server validation, exact section count, length/start, allowed commands,
and ordered instrument identity. Review reply language independently; do not count
unparseable output as a language pass. Timing and extra request bytes are reported.
Mixed evidence or a baseline that does not reproduce the issue means no adoption.
This is a screening test, not proof of a population-level reliability guarantee.

Offline check:

```
PYTHONDONTWRITEBYTECODE=1 python tool/ai_v3_eval/evaluate_pitch_presentation.py --output /tmp/pro4-pitch-presentation.json
```

Only `--execute-live` authorizes provider calls (normal usage costs). No runtime
or bridge change is needed to run the comparison.

Method: task-specific executable checks, fixed scenarios, and independent review,
consistent with [OpenAI evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices).

## Completed results

40 calls completed. **Do not adopt:** candidate 17/20 is below the predeclared
18/20 gate. It improves this sample, but does not eliminate first-pass pitch
failures. Both variants had one output truncated at the existing token budget;
neither had a provider timeout. Do not raise that budget based on this experiment.

| Metric | Baseline | Adjacent summary candidate |
| --- | ---: | ---: |
| Executable first-pass plan, correct scope/instrument | 13/20 | 17/20 |
| Pitch failures | 6 | 2 |
| Truncated output | 1 | 1 |
| Other observed scope/instrument failures | 0 | 0 |
| Wrong-language replies among valid plans | 0 | 0 |
| Median provider-call-plus-validation time | 15.933 s | 15.403 s |
| p95 (nearest rank, all attempts) | 30.821 s | 23.368 s |
| Maximum | 50.205 s | 51.574 s |
| Mean input tokens | 17,337.6 | 19,154.2 |

All 30 valid-plan replies were independently read and were English. This was a
manual language review, not a model self-grade or a runtime language detector.
Invalid/truncated responses are not counted as language successes. Musical
quality and factual accuracy of subjective musical descriptions were not graded.

| Scenario successes | Baseline | Candidate |
| --- | ---: | ---: |
| Exact two-section clarification follow-up | 0/4 | 2/4 |
| Low-register guitar | 3/4 | 4/4 |
| Range-limited flute | 4/4 | 4/4 |
| Sparse drums | 4/4 | 4/4 |
| Ordered instrument switch | 2/4 | 3/4 |

The candidate still failed twice on the original follow-up scenario. The nearby
summary is not a reliable solution to that user-facing case yet. The trial does
not prove that context placement caused every original error, nor establish a
production failure rate. Results from the earlier instruction-paragraph trial
must not be compared directly: this experiment uses a different synthetic catalog
and sparse drum fixture; only its paired baseline/candidate comparison is valid.

The added summary costs 5,187–5,237 bytes per tested contract body (about 5.9%),
and 1,816.6 additional mean input tokens (about 10.5%). It does not reduce request
weight. Cached usage and timing may vary; timings are not a production forecast.

Artifacts: `/tmp/pro4-pitch-presentation.json` retains synthetic raw results;
`/tmp/pro4-pitch-presentation.log` contains progress and component sizes.
`/tmp/pro4-pitch-presentation-tests.log` records **300 passing backend tests**,
including legacy compatibility and deterministic provider-body baselines.
`git diff --check` passed. No cache artifacts were added.

Only evaluation tooling/tests and this report changed. No runtime prompt,
schema, model, timeout, validation, or repair changes were adopted. The local app
and bridge were not restarted or modified. No commit, push, PR update, deployment,
or production mutation. The existing client identity fix remains intact.
