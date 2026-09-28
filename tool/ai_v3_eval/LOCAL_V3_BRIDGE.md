# Sealed local V3 bridge

This bridge runs the real contract-6 Lambda handler behind a loopback-only HTTP
server. It replaces authentication, quota persistence, analytics, monitoring,
secrets, and the AI provider with deterministic in-memory test seams.

It makes no OpenAI, AWS, PostHog, Sentry, or other external network calls. It
does not emulate real provider latency or production networking, so its results
must not be used alone to justify a timeout or schema change.

## Automated verification

From `backend/llm_proxy`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.test_v3_local_bridge -v
```

The suite sends real HTTP requests over `127.0.0.1` and covers product-max
success, measured delay, timeout, upstream error, invalid output, semantic
repair success/failure, settlement, and route isolation. Existing Dart tests
separately lock the client request timeout and response/error parsing.

## Run manually

From the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tool/ai_v3_eval/local_v3_bridge.py \
  --port 8765 \
  --scenario success
```

The server always binds to `127.0.0.1`; it cannot be exposed by a host option.
Available scenarios are:

- `success`
- `timeout`
- `upstream_error`
- `invalid_output`
- `semantic_repair_success`
- `semantic_repair_failure`
- `capability_repair_success`
- `capability_repair_failure`

The default `standard` transport retains the current 27-second provider
ceiling. The isolated long-running path is available explicitly with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tool/ai_v3_eval/local_v3_bridge.py \
  --transport long \
  --provider-timeout-seconds 105
```

Long mode sends a REST API v1 event through `api_responses_v3_rest.handler`,
uses a simulated 115-second Lambda window, and permits a provider deadline up to
105 seconds. Standard mode still sends the existing HTTP API v2 event and
rejects provider deadlines above 27 seconds.

An optional `--delay-ms` adds real local provider delay. Values at or beyond
the configured `--provider-timeout-seconds` produce the same controlled timeout
path as the backend. The provider timeout may be reduced to make tests fast. Its
maximum is 27 seconds in standard mode and 55 seconds in long mode.

Health and privacy-filtered measurements are available at:

```text
http://127.0.0.1:8765/_local/health
http://127.0.0.1:8765/_local/cloudwatch-export
```

The second endpoint emits CloudWatch-compatible JSON accepted by
`analyze_v3_production_measurement.py`. It excludes prompt traces, users,
projects, request IDs, provider response IDs, prompts, context, plans,
resources, and schemas.

## Point a debug desktop client at the bridge

Use a signed-in debug session so the client can obtain a non-empty token. The
bridge does not validate or forward that token.

```sh
flutter run -d macos \
  --dart-define=LLM_PROXY_API_BASE_URL=http://127.0.0.1:8765 \
  --dart-define=AI_V3_PRIMARY_ENABLED=true \
  --dart-define=AI_V3_RESOURCE_REFS_ENABLED=true
```

To exercise the opt-in long-route selection without changing any existing API
configuration, keep the bridge running and launch with both long-route values:

```bash
flutter run \
  --dart-define=AI_V3_LONG_PATH_ENABLED=true \
  --dart-define=AI_V3_LONG_API_BASE_URL=http://127.0.0.1:8765
```

The flag or URL alone does nothing. With both present, only the V3 planner uses
that base URL and its 130-second client window. V1 and all other proxy calls keep
their existing URL and timeout. The client does not fall back or resubmit after
a long-route timeout.

The checked-in slow integration test starts the long bridge on an ephemeral
loopback port, waits 40 seconds for its deterministic provider, and verifies
the real Dart client succeeds once with a 130-second client window:

```sh
PRO4_RUN_SLOW_LOCAL_LONG_PATH=1 \
flutter test test/ai_v3_long_path_local_integration_test.dart
```

This changes only the debug process configuration. Do not put the localhost
URL into checked-in production defaults.

To exercise the client-side timeout quickly, start a delayed bridge with a
three-second backend deadline and compile the debug client with a one-second
V3 timeout. A disconnected client is recorded safely without crashing the
bridge:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tool/ai_v3_eval/local_v3_bridge.py \
  --scenario success \
  --delay-ms 2000 \
  --provider-timeout-seconds 3

flutter run -d macos \
  --dart-define=LLM_PROXY_API_BASE_URL=http://127.0.0.1:8765 \
  --dart-define=AI_V3_REQUEST_TIMEOUT_SECONDS=1
```

Stop the bridge with Ctrl-C. Do not commit exported measurements; save them
under `/tmp` when needed.

## Bounded live-provider measurement

`measure_v3_live_provider.py` is separate from the listening bridge. It sends
exactly three fixed synthetic control requests, then exits: restart playback on
`small`, transpose a known MIDI clip on `product_max`, and rename a known row on
`large_project`. It has no option for arbitrary prompts, scenarios, or request
counts. It retains only privacy-safe timing, size, usage, status, validation,
and exact semantic-result metadata in `/tmp/pro118-one-shot-baseline.json`.

The live run must be explicitly acknowledged and incurs normal OpenAI usage:

```sh
LLM_API_KEY_PARAMETER_NAME=/path/to/encrypted/parameter \
AWS_REGION=ap-northeast-2 \
PYTHONDONTWRITEBYTECODE=1 python3 tool/ai_v3_eval/measure_v3_live_provider.py \
  --execute-live
```

The requests use the current contract-6 provider body, `gpt-5.6-luna`, low
reasoning effort, the contract-derived output budget, and the 105-second long
path deadline. The tool does not call the production Mixroom API or mutate
production application data, and it does not retry failed calls.
