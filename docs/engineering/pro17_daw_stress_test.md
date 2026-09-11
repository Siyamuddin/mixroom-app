# PRO-17 DAW stress test

Use the deterministic generator to create real Mixroom projects without
checking large media fixtures into Git.

Generate the two baseline project shapes in a disposable location:

```sh
dart tool/generate_daw_stress_project.dart \
  --output /tmp/pro17-99-rows \
  --rows 99 \
  --clips 400 \
  --min-clip-seconds 30 \
  --max-clip-seconds 300 \
  --name "PRO-17 99 Rows 400 Long Clips" \
  --bundle /tmp/PRO-17-99-rows-400-clips.mixroom

dart tool/generate_daw_stress_project.dart \
  --output /tmp/pro17-40-rows \
  --rows 40 \
  --clips 400 \
  --name "PRO-17 40 rows 400 clips"
```

The rows alternate between audio and MIDI. Audio clips share one generated
48 kHz WAV source. MIDI clips use Mixroom's built-in Basic Synth, so the result
does not depend on third-party plugins. The long fixture contains real clips
from 30 seconds to 5 minutes, with heavy overlap across the beginning,
1-minute, 5-minute, 15-minute, and 20-minute timeline zones.

To expose a generated project directly on macOS, make `--output` a new child
directory inside the `mixroom_projects` application documents directory. To
use the identical fixture on Android or iOS, transfer the generated `.mixroom`
bundle to the physical device and open/import it with Mixroom. The generator
refuses to overwrite an existing directory or bundle.

## Baseline procedure

Test each operation after the project is fully loaded and idle:

1. Add an audio row.
2. Remove an empty row near the middle.
3. Move a middle row up, then down.
4. Add an audio clip to an existing audio row.
5. Delete that clip.

Run the same actions at 20, 100, 200, and 400 clips. Capture at least 20 warm
samples per action and report median, p95, and maximum wall time. Project-load
time is useful context but is not part of the action latency acceptance check.

Compare both fixture shapes. A slowdown only in the 99-row project implicates
row/graph handling; a slowdown in both shapes implicates clip-wide work. The
99-row shape intentionally leaves one slot below Mixroom's native 100-row limit
so the add-row action can be measured.

## Isolated capacity-integration baseline

Build with the explicit compile-time flag. Performance conclusions must use a
profile build on a physical device; debug timings are not representative.

```sh
/usr/bin/caffeinate -di /usr/bin/sandbox-exec -f tool/pro17_offline_macos.sb \
  flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/pro17_capacity_benchmark_test.dart \
  -d macos --profile --no-pub \
  --dart-define=PRO17_PERF=true \
  --dart-define=PRO17_LABEL=baseline_offline \
  --dart-define=POSTHOG_API_KEY= \
  --dart-define=SENTRY_DSN= \
  --dart-define=POSTHOG_HOST=http://127.0.0.1:1 \
  --dart-define=APP_API_BASE_URL=http://127.0.0.1:1 \
  --dart-define=SUBSCRIPTION_API_BASE_URL=http://127.0.0.1:1 \
  --dart-define=LLM_PROXY_API_BASE_URL=http://127.0.0.1:1
```

This harness requires the build flag and an attached evaluation controller.
It fails before opening a project if analytics is configured or the service
endpoints are not loopback-only. Native PostHog auto-initialization must remain
disabled. Do not run a baseline with the production analytics defaults.
On macOS the sandbox wrapper additionally denies non-loopback outbound
connections for the runner and its children. If dependencies are not available
locally, stop rather than removing this restriction during a benchmark run.
`caffeinate` prevents idle display/system sleep only while the runner is alive.
No AI prompts are submitted. Every measurement line is single-line JSON
prefixed with `[PRO17_PERF]`.

The probe reports:

- `operation_start`, `operation_phase`, and `operation_end` for add/remove/move
  row and add/delete clip actions;
- `operation_visible_frame`, measuring through the first rendered UI frame;
- `operation_end.frame_already_scheduled` and `operation_event_loop_yield`,
  distinguishing application-frame scheduling from continued UI-isolate work;
- `slow_frame` for Flutter frames over 32 ms;
- `event_loop_stall` when the UI isolate fails to tick for at least 150 ms.

The integration benchmark waits for the frame scheduled by the editor mutation
itself. It does not inject an additional test-driven frame into the measured
interval.

The same operations appear as `PRO17 ...` timeline tasks in Flutter DevTools.
Each test creates its own temporary project root, never the user's project
directory. Measurements are written to `measurements.jsonl` in that root;
the completion record prints its path. The default matrix is 40/99 rows ×
20/100/200/400 clips, two runs, two warm-ups followed by twenty measured samples
per action. Empty-row and populated-row deletion are separate actions. Each
action is undone before the next sample; model counts and undo admission are
checked. These assertions are not a substitute for full native readback,
export, fault injection, or candidate capacity acceptance.

Analyze completed measurement files with:

```sh
PYTHONDONTWRITEBYTECODE=1 python tool/analyze_daw_capacity_benchmark.py \
  /tmp/example-baseline/measurements.jsonl > /tmp/pro17-summary.json
```

The analyzer rejects failed actions, duplicate measurements, invalid timing,
and missing first-visible-frame records. Check that every required shape,
action and run has twenty samples; do not treat a partial run as a full matrix.
Some phase intervals include preparation before the native call, so their
labels do not establish isolated native CPU costs.

Keep the app foregrounded and avoid debugger sampling or concurrent builds
during measurement. Repeat affected cases if those conditions are violated.
The harness rejects a non-resumed lifecycle before or after an action and
times out a missing first frame rather than waiting indefinitely in background.
The matrix uses one continuous `testWidgets` lifecycle: separate tests reset
Flutter's lifecycle state even when the native window remains active. Each
synthetic editor is still disposed between cases. Startup waits up to thirty
seconds for genuine foreground readiness, outside the measurement interval.
If a case is interrupted, exclude its entire measurement file. Completed cases
can be retained; rerun only incomplete shapes with `PRO17_ROWS` and
`PRO17_CLIPS`, using the same label, instrumentation, fixture seed, run count
and sample count. Validate the final matrix has each shape exactly once.
Stop the owned test app explicitly after the runner completes; the macOS
integration runner can leave the application running. Do not terminate other
Mixroom instances. The earlier PRO-17 AI timing changes are not included.
