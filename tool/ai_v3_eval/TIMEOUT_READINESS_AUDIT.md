# PRO-4 timeout headroom audit — 2026-09-08

**Historical audit, superseded by the approved local implementation.** After this
audit, the owner confirmed there are no distributed clients depending on the 55s
long path, so its replacement does not require negotiation. AWS approved the
120,000 ms quota. The normal local path now uses 105/115/120/130; deployment has
not occurred. The test-only override bridge was removed, and its 75s check now
runs against the actual path as `test/ai_v3_extended_long_path_local_test.dart`
with `PRO4_RUN_EXTENDED_LONG_PATH=1`. The original findings below are retained
as dated evidence, not current operating instructions.

Local test preparation only. No runtime deadline, template, client configuration,
manual bridge, production deployment, or quota request was changed.

## Current facts

| Path | Provider budget | Lambda | Gateway | Client |
|---|---:|---:|---:|---:|
| Original HTTP V3 defaults | 27s | 30s | 30s | 35s |
| Existing opted-in long REST path | 55s | 60s | 65s | 70s |
| Isolated experimental candidate | 105s | 115s | proposed 120s | test-only 130s |

Current values are source/template defaults, not a fresh inventory of all deployed
functions or distributed clients. A read-only Service Quotas lookup in
`ap-northeast-2` confirmed `L-E5AE38E3` (maximum integration timeout) is **65,000 ms**,
adjustable. It did not authorize or request an increase. No production logs were read.

AWS documents a non-increasable 30s HTTP API integration ceiling, and adjustable
Regional REST integration timeouts; an increase can require a regional throttle
quota reduction:

- [HTTP API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html)
- [REST API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)

The real handler has an absolute 55s ceiling. Setting its existing environment
values to 105 alone still produces 55. Repair shares the initial provider deadline;
it does not get a fresh budget. The handler also reserves two seconds of remaining
Lambda time when calculating a provider attempt's permitted duration.

## Experiments

`timeout_candidate_bridge.py` temporarily substitutes limits ONLY inside its own
fake-provider test process, using mocks restored on exit. It has no live-provider
mode and is not imported by runtime handlers or the manual live bridge.

- A real loopback request with a deliberate **75-second fake-provider delay**
  completed through the REST adapter and client service. The test injects a 130s
  client timeout; it also asserts that the normal route still resolves to 70s.
- Fake-clock handler checks: 75s success; provider exceeding 105s returns controlled
  504; 80s first pass leaves 25s for repair; 104s first pass leaves only 1s, and a
  2s repair times out. At most two attempts and exactly one finalization/release.
- Candidate Lambda-margin checks preserve the existing two-second minimum margin.
- Current-runtime checks prove the ordinary absolute ceiling remains 55s after
  experiments. No candidate settings are active in the running app.

The loopback experiment does **not** emulate an AWS gateway or establish 120s
deployment feasibility, live-provider latency, musical quality, or cost equivalence.

Results: **340 AI-backend tests passed**, **14 client planner/route tests passed**,
and the opt-in 75s loopback test passed. `git diff --check` passed; no Python
bytecode artifacts were generated. These are focused AI compatibility results,
not a claim that the unrelated application-backend failures have been fixed.

Reproduce the slow test without any model calls:

```sh
PRO4_RUN_TIMEOUT_CANDIDATE=1 PRO4_PYTHON_BIN=/path/to/python \
  flutter test --no-pub test/ai_v3_timeout_candidate_local_test.dart
```

The test starts a private ephemeral-port fake bridge and stops it automatically.
Without the opt-in environment variable, this slow test is skipped.

## Requirements before adoption

1. **Preserve both existing client populations.** Original HTTP clients wait 35s;
   existing long-path clients wait 70s. Extending the same endpoint unconditionally
   would allow backend work to outlive the latter. Use explicit versioned deadline
   capability negotiation or a separately versioned route before enabling 105s.
   Unknown/missing capability must retain the existing route's budget. No automatic
   retry through another endpoint after timeout.
2. Implement and test any such runtime gating as a separate approved local change.
   This experiment deliberately does not add a shipping capability or route.
3. A 120s REST integration needs quota approval of at least **120,000 ms**, followed
   by separately approved configuration/deployment after review and merge. The
   current 65,000 ms approval is insufficient. Nothing was submitted to AWS.
4. Review concurrency/throttles, usage reservation, cancellation/late-response UX,
   and monitoring before activation. Longer waits increase resource occupancy and
   do not guarantee every request will finish. Do not claim zero extra cost.

Next local implementation should address deadline negotiation, not unrelated
command/note/context limits. Keep the current running app and manual session on
their existing deadlines until that change is explicitly adopted.
