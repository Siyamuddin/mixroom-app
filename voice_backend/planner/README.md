# Local planner worker

The Python API imports `planner.bridge.plan_voice_request` and
`planner.bridge.resolve_mix_request`. Both are async functions returning
`{"httpStatus": int, "response": dict}`. The voice input stays
`{sessionId, commandId, request, sessionState}`.

This package reuses MixRoom's tested TypeScript planner and canonical V3 schema
validators in a short-lived Node child. It does not run n8n, require Lovable
Cloud, or create another HTTP service. OpenAI calls and optional Jev
classification happen directly inside the child. The native app still executes
and verifies every DAW operation.

Requirements:

- Python 3.11 or newer; this package uses only the standard library.
- Node 22.18 or newer, available as `node` in the container's `PATH`.
- One FastAPI/Uvicorn application process for the documented total concurrency
  cap. Each Python event loop admits at most two worker children; additional
  requests receive `503 planner_busy` without being queued.

The server passes a settings object with `openai_api_key`, `typesafe_api_key`,
`openai_model`, and `typesafe_model` string attributes. Only the OpenAI key is
required for voice planning. Jev can be absent or unavailable; structured OpenAI
routing remains available and diagnostics disclose the fallback. Default models
are `gpt-5.4-2026-03-05` and `jev-1.13.0`. Mix compatibility passes through locally
calculated actions and explicitly labels that behavior; it requires no AI key.

Keys enter the child only through its environment. Neither request JSON nor
command arguments contain credentials. The child environment excludes
`NODE_OPTIONS`, preload hooks, and unrelated application secrets. Requests cannot
select scripts, fetch implementations, or provider endpoints. Errors never
return raw child stderr, exceptions, or provider error bodies.

Resource limits are 4.6 MB for the worker input envelope, 2 MB for stdout,
64 KB for stderr, and 75 seconds for the whole exchange. Timeout, caller
cancellation, or output overflow terminates and reaps the child. Each Node
process uses a 192 MiB V8 old-space ceiling; this is **not** a total resident
memory limit, so the Docker container should also have a memory limit.

The planner still validates its own tighter project/provider limits, keeps one
immutable snapshot detail lookup at most, and rejects invalid typed commands.
Recording without a stated duration uses the native default of 10 seconds.
Explicit durations must stay within 1–60 seconds. Seconds and bars cannot both
be supplied; bars must be whole numbers and remain within 60 seconds after
tempo and time-signature conversion.

From `voice_backend/`, run:

```sh
python3 -m unittest discover -s tests -p 'test_planner_worker.py' -v
node --experimental-strip-types --test planner/tests/planner.test.ts
```

The Python suite runs the real child process with a test-only preload that
mocks provider HTTP responses. Production code has no preload configuration or
injection option. Tests cover the real process boundary, canonical plans,
session actions, Jev fallback, expiry-independent worker timeouts, output caps,
credential separation, cancellation cleanup, and concurrency limits. They do
not establish live provider availability or microphone/audio behavior.
