# Bluetooth 2.0 Reliability Plan and Technical Specification

## Document status

- Status: the macOS V2 playback and live-output checkpoints are complete. The
  Android Legacy baseline, Android V2 built-in-speaker foundation, and Android
  V2 preconnected Bluetooth media playback have passed their initial
  physical-device gates. Android live-output coordination has also passed its
  focused Samsung/Sony hardware gate.
- Applies to: Android, iOS, and macOS.
- Excludes: Windows and every other unsupported platform.
- Current production implementation: Legacy Bluetooth only.
- Proposed implementation: Bluetooth 2.0, developed beside Legacy and selected
  only in internal/test builds until release gates pass.
- Change rule: each delivery phase below requires a separate review and explicit
  approval before code is changed. Approval of this document does not approve
  all implementation phases.

This document is the authority for the proposed Bluetooth 2.0 behavior. It is
also a guard against accumulating another series of route-specific patches.
If implementation pressure conflicts with the invariants or simplicity budget
here, stop and revise the plan first.

## Executive decision

Bluetooth 2.0 should be a small route-aware audio lifecycle, not a replacement
Bluetooth stack. The operating system continues to own pairing, codecs, radio
transport, and device discovery. Mixroom owns only the decisions an audio
application cannot delegate safely:

- whether input is open;
- playback versus recording intent;
- safe input/output combination;
- JUCE device teardown and reopening;
- requested hardware rate and buffer policy;
- verification of the configuration the OS actually accepted; and
- bounded recovery when a route disappears or cannot be configured.

The product should accept normal Bluetooth transport latency. It should not add
a universal 300 ms application delay. Clean, stable audio and crash safety are
more important than low latency on Bluetooth.

## Goals

1. Clean Bluetooth playback without persistent crackling, jitter, or dropouts.
2. Crash-free connect, disconnect, reconnect, background, and interruption
   handling.
3. High-quality media output during ordinary playback; no silent switch to a
   call-quality headset profile.
4. Input closed during ordinary editing and playback.
5. Safe recording with a verified non-Bluetooth input when Bluetooth output is
   active.
6. The same user-facing contract on Android, iOS, and macOS where that improves
   reliability.
7. Legacy and Bluetooth 2.0 available side by side for controlled A/B testing.
8. A compact implementation with one policy, one coordinator, thin adapters,
   and bounded recovery.

## Non-goals

- Implementing Bluetooth codecs, pairing, device firmware workarounds, or radio
  transport.
- Eliminating Bluetooth's inherent latency.
- Making live Bluetooth monitoring feel like wired monitoring.
- Supporting Bluetooth headset microphones in the initial V2 release.
- Forcing identical native settings on different operating systems.
- Automatically creating macOS aggregate/combiner devices.
- Changing project or export sample rates when the hardware route changes.
- Removing Legacy as part of this project.
- Adding Windows support.

## What consistency means

Consistency means the same observable product rules, not identical native API
calls or buffer values.

| User-visible situation | Android | iOS | macOS |
| --- | --- | --- | --- |
| Open project | Playback only; input closed | Playback only; input closed | Playback only; input closed |
| Bluetooth playback | Prefer high-quality media route | Prefer A2DP/media output | Use selected Core Audio Bluetooth output |
| Normal Bluetooth latency | Accepted | Accepted | Accepted |
| Live monitoring | Off by default | Off by default | Off by default |
| Bluetooth headset microphone | Rejected initially | Rejected initially | Rejected initially |
| Recording with Bluetooth output | Prefer built-in/default non-Bluetooth mic | Prefer built-in mic | Prefer built-in/default non-Bluetooth mic |
| Unsupported duplex combination | Mute simultaneous playback or fail clearly | Mute simultaneous playback or fail clearly | Mute simultaneous playback or fail clearly |
| Disconnect | Quiesce, fall back, verify, resume if safe | Quiesce, fall back, verify, resume if safe | Quiesce, fall back, verify, resume if safe |

## Current Legacy implementation

### Shared Flutter/editor behavior

The editor currently owns significant route behavior in addition to native and
JUCE code:

- project opening loads input devices and requests recording-input prewarming;
- route information is cached and refreshed from several editor paths;
- Android route refreshes are deferred around engine-critical work;
- recording preflight contains platform branches;
- live monitoring is normally disabled for Bluetooth output, but an advanced
  override exists;
- Bluetooth microphone choices can be remembered on Android/iOS, while macOS
  blocks Bluetooth input;
- recording route policy is periodically refreshed; and
- Android may run delayed post-record Bluetooth restoration.

This is understandable historical repair work, but ownership is distributed.
The editor can request a refresh while JUCE or a native helper is already
changing the route, and requested state is sometimes used without one complete
read-back snapshot.

### Android Legacy behavior

- JUCE runs through Oboe/AAudio.
- Startup normalizes `AudioManager` to normal mode and repairs playback-only
  output if inputs or communication routing linger.
- A2DP, SCO, and Bluetooth LE outputs are currently collapsed into a general
  Bluetooth-output classification; Bluetooth SCO/LE input is identified
  separately.
- Android editor prewarm requests currently return early, so project loading is
  effectively playback-only on Android.
- JUCE applies an Android stability buffer heuristic and may avoid some
  buffer-only device reopens.
- Recording opens input through JUCE. Stop-record logic normalizes communication
  mode/SCO and can perform a hard playback-only reset plus delayed cleanup.
- Route refresh is partly editor-driven and partly driven by JUCE device-manager
  change callbacks; there is no single generation-tagged transaction owner.

Strengths to retain: playback-only recovery, media-route normalization, active
output validation, xrun-capable Oboe infrastructure, and bounded engine-critical
sections.

Risks to address: coarse A2DP/SCO/LE reporting, user settings leaking into a
Bluetooth route, no complete actual-state snapshot, overlapping repair paths,
and delayed post-record work that can race a newer route.

Android Legacy baseline evidence (2026-08-10, Samsung SM-S918N, built-in output,
Bluetooth disconnected): the on-device meter integration test produced
measurable output for Upright Piano preview and timeline playback, a second MIDI
row, Basic Synth, sampled round-robin notes, and live MIDI note-on/off. A manual
normal-app check confirmed that MIDI and audio played normally. This establishes
the pre-V2 regression baseline; it is not evidence about Bluetooth routing.

### iOS Legacy behavior

- JUCE uses AVAudioSession/Core Audio.
- Initial JUCE setup can request input channels before clearing them, and the
  editor may prewarm recording input after project load when not playing.
- Route information is read from `AVAudioSession`, but the plugin does not own a
  single direct, generation-tagged AVAudioSession route-change transaction.
- Recording can prefer a non-Bluetooth input, then request another asynchronous
  JUCE route refresh.
- Stop/shutdown clears preferred input and asks the route to refresh.
- Disconnect behavior is therefore spread across AVAudioSession, JUCE device
  callbacks, editor refreshes, and asynchronous recovery. Reported crashes when
  Bluetooth is disconnected while the app runs must be treated as a primary
  safety defect.

Strengths to retain: native route metadata, built-in-input preference, and JUCE
device handling.

Risks to address: transient/persistent input opening, asynchronous work that can
outlive a removed route, missing generation invalidation, and unclear atomicity
between session configuration and JUCE reopening.

### macOS Legacy behavior

- JUCE uses Core Audio.
- Engine startup is already playback-only to avoid unsafe aggregate/combiner
  creation with Bluetooth output.
- Core Audio metadata and name fallback are used to identify Bluetooth inputs.
- Both the editor and JUCE prefer a safe non-Bluetooth input for recording.
- The editor may still prewarm that safe input after project loading.
- Output route reporting is less complete than input protection, and route
  coordination remains distributed.

Strengths to retain: playback-only startup, Core Audio transport inspection,
safe input selection, and aggregate-device avoidance.

Risks to address: prewarming, incomplete output facts, and duplicated ownership
between the editor and native/JUCE layers.

### Root architectural problems

| Problem | Consequence |
| --- | --- |
| Route ownership split across Flutter, native code, and JUCE | Overlapping refreshes and hard-to-reproduce races |
| Input lifecycle tied to project/device loading | Possible HFP/call-quality output and needless route churn |
| Requested rate/buffer treated as meaningful without one verified snapshot | False success and hidden resampling |
| Route categories too coarse | A2DP, SCO/HFP, and LE behavior can be confused |
| Delayed repair chains | Older work can modify a newer route |
| Different recording policy by platform | Inconsistent user behavior and testing |
| Limited diagnostics | Crackling cannot be tied confidently to profile, rate, buffer, callback timing, or xruns |

## Bluetooth 2.0 invariants

1. Opening a project is output-only. Project loading never opens the microphone.
2. Bluetooth is primarily a high-quality playback route with normal transport
   latency.
3. Input opens only for `preparingRecording`, `recording`, or deliberate
   supported `monitoring` intent.
4. Input closes immediately when none of those intents remains.
5. Bluetooth headset microphones are disabled on all three platforms initially.
6. Bluetooth live monitoring is disabled by default and has no V2 override in
   the initial release.
7. Project/export rate remains independent from active hardware rate.
8. The adapter queries capabilities, requests a conservative configuration,
   reads back actual state, and treats only verified state as success.
9. One coordinator serializes every effective route transition.
10. Native route notifications carry monotonically increasing generations.
11. Work from an older generation cannot apply after a newer route event.
12. Duplicate notifications do not cause repeated device rebuilding.
13. Recovery is finite: one primary attempt, at most one safe fallback, then a
    clear failed state.
14. No recursive refreshes, unbounded timers, or infinite delayed retries.
15. A removed device is never referenced after disconnect invalidation.
16. Exactly one implementation—Legacy or V2—runs for an editor session.

## Compact architecture

Bluetooth 2.0 contains only four concepts:

1. `AudioRouteSnapshot`: immutable facts read from native APIs and JUCE.
2. `AudioRoutePolicyV2`: a pure function from facts, capabilities, and intent to
   one desired configuration.
3. `AudioRouteCoordinatorV2`: the sole serialized transition owner.
4. Thin Android, iOS, and macOS adapters.

Flutter owns user intent and presentation. Native/JUCE code owns safe teardown,
platform session configuration, device reopening, actual-state read-back, and
validation. The editor must not contain platform-specific repair policy in V2.

### Simplicity budget

- Four coordinator states only: `stable`, `preparingInput`, `reconfiguring`,
  and `failed`.
- Four intents only: `playbackOnly`, `preparingRecording`, `recording`, and
  `monitoring`.
- One transition queue.
- One immutable snapshot shape.
- One shared policy table.
- At most one fallback per transition.
- No permanent polling in Flutter.
- No platform adapter may invent product policy.
- Replaced V2-path logic is deleted from V2 rather than layered underneath it;
  Legacy remains separate and untouched.

## Proposed interfaces

### `BluetoothImplementation`

- `legacy`
- `v2`

The locally persisted selection is read before engine initialization. Switching
requires closing and reopening the editor/engine. Hot-swapping while playing or
recording is forbidden.

### `AudioRouteSnapshot`

Required fields:

- implementation, platform, generation, and transition ID;
- stable native input/output identifiers and display names;
- input and output route kinds;
- active input/output channel counts and whether input is open;
- requested and actual sample rate and buffer size;
- transport/profile evidence, including A2DP, HFP/SCO, and LE where observable;
- xrun count and callback timing summary;
- platform audio/session mode;
- stream state/status;
- Android audio API, performance mode, frames per burst, and capacity where
  available; and
- explicit `unknown`/`unavailable` values rather than invented defaults.

Route kinds:

- built-in;
- wired;
- USB/external;
- Bluetooth with profile unavailable;
- Bluetooth media;
- Bluetooth headset/duplex;
- Bluetooth LE; and
- unknown.

### `DesiredAudioRouteConfiguration`

- desired input and output selection;
- desired input channel count;
- hardware-rate preference, not project-rate mutation;
- lower and upper buffer bounds;
- monitoring permission;
- whether a non-Bluetooth input is mandatory; and
- fallback behavior.

### `AudioRouteTransitionResult`

- status: success, verified fallback, or failure;
- actual post-transition snapshot;
- human-readable reason;
- stable diagnostic code; and
- elapsed transition time.

### Plugin contract

Proposed methods:

- `getAudioRouteSnapshotV2`
- `setAudioRouteIntentV2`
- `applyAudioRouteConfigurationV2`
- `getAudioRouteDiagnosticsV2`

Proposed event:

- `audioRouteChangedV2`, containing generation, cause, and a native snapshot.

One native `apply` is atomic from Flutter's perspective:

1. reject stale generation;
2. fade or mute and quiesce the old route;
3. stop using removed devices;
4. close obsolete input;
5. configure the platform session/mode;
6. choose safe devices;
7. reopen JUCE;
8. read actual state;
9. validate; and
10. return success, one verified fallback, or failure.

## Common policy

| Intent and route | Input | Hardware-rate policy | Buffer policy | Monitoring |
| --- | --- | --- | --- | --- |
| Playback, built-in/wired/USB | Closed | Use actual native-supported rate | Route-native/supported | Off |
| Playback, Bluetooth (profile known or unavailable)/LE | Closed | Prefer 48 kHz, accept/read actual | Conservative, bounded, route-supported | Off |
| Preparing/recording with Bluetooth output | Mandatory safe non-Bluetooth input | Verify actual after reopen | Stability-oriented and bounded | Off |
| Preparing/recording without Bluetooth | Selected safe input | Verify actual | Route-supported | Off unless explicitly supported |
| Monitoring without Bluetooth | Selected safe input | Verify actual | Route-supported | Explicit intent only |
| Monitoring with Bluetooth | Unsupported initially | — | — | Off |

The first diagnostic default for Bluetooth should be 48 kHz and at least a
1024-frame application/JUCE buffer, because it is conservative and directly
tests the current underrun hypothesis. It is not a universal final constant.
Adapters must select supported values, observe native burst/capacity data where
available, and record the actual accepted settings. Any upper bound must be
defined before implementation and validated on hardware; a provisional 2048
frames is a test ceiling, not a promise that every platform exposes that exact
buffer.

If xruns grow after stabilization, the native adapter may grow buffering in
native burst-sized steps within the approved bound. It must not repeatedly
reopen a stable route or impose an artificial 300 ms delay.

## Input and profile policy

- Do not prewarm input at project load.
- Request microphone permission without opening an audio input stream.
- Open input immediately before record preparation/count-in, not merely because
  a track exists or the editor is open.
- Prefer the built-in microphone, then a verified non-Bluetooth external input.
- Never select an input by display-name guessing when native transport metadata
  is available.
- After input opens, verify that output remains a high-quality media route.
- If opening safe input forces HFP/SCO/call-quality output, close input and
  either mute simultaneous playback during capture or fail before capture with
  a clear explanation.
- After recording/monitoring ends, close input, restore playback-only platform
  configuration, and verify the effective output profile.

Initial user message for a rejected combination:

> Bluetooth playback cannot stay in high-quality mode with the available
> microphone. Choose another input, disconnect Bluetooth, or record without
> simultaneous playback.

## Route-transition rules

### Connect

1. Receive native route event and increment generation.
2. Debounce duplicate facts, not meaningful changes.
3. Quiesce current output if reopening is required.
4. Apply playback-only Bluetooth policy.
5. Read back and verify high-quality output, actual rate, buffer, and channels.
6. Resume only after verified success/fallback.

### Disconnect

1. Immediately invalidate the removed device generation.
2. Fade/mute and stop callbacks from using that device.
3. Close obsolete input and cancel stale recording preparation.
4. Choose the system-safe fallback output.
5. Reconfigure the platform and reopen JUCE once.
6. Verify actual fallback state.
7. Resume if safe; otherwise enter `failed` with a recoverable user action.

### Start recording

1. Confirm permission without prewarming.
2. Set `preparingRecording` intent.
3. Choose and open safe non-Bluetooth input.
4. Verify output profile, active channels, actual rate/buffer, and stream state.
5. Start file capture only after successful validation.
6. If validation fails, close input and return to verified playback-only state.

### Stop recording

1. Finalize the recording file before tearing down required input.
2. Set `playbackOnly` intent.
3. Close input and restore platform playback mode.
4. Reopen/verify high-quality output once.
5. Resume transport only if requested and verified safe.

### Background, interruption, and shutdown

- Invalidate in-flight generations before releasing native resources.
- Never deliver a route callback to a disposed coordinator.
- On resume, read one fresh snapshot and reconcile only if effective facts
  differ.
- Shutdown closes input and observers before destroying JUCE/native ownership.

## Platform adapter responsibilities

### Android

- Use native `AudioDeviceInfo` types to distinguish A2DP, SCO, and Bluetooth LE.
- Keep media/music usage and `AudioManager.MODE_NORMAL` for playback.
- Clear communication-device/SCO routing before media playback.
- Preserve output-only startup.
- Prefer built-in/non-Bluetooth input by native device identity.
- Report actual AAudio/Oboe API, performance mode, sample rate, callback/buffer
  sizes, capacity, frames per burst, stream state, and xruns when available.
- Choose low-latency versus normal/stability performance mode from observed
  route behavior; do not force low latency merely because it works on speakers.
- Reopen only when effective route/configuration changes.
- Provide one supported fallback if the preferred AAudio configuration fails.

Questions that Android diagnostics must answer before tuning:

- Is output actually A2DP/LE media or SCO/duplex during the bad sound?
- What rate and buffer did Oboe actually accept?
- Are xruns growing continuously or only during transition?
- Is low-latency performance mode still active on Bluetooth?
- Does JUCE/Oboe expose enough burst/capacity data, or is a small diagnostic
  bridge required?

### iOS

- Observe `AVAudioSessionRouteChangeNotification` directly.
- Invalidate and quiesce an unavailable device before asynchronous rebuilding.
- Use an explicit playback category/mode for output-only intent.
- Use an explicit recording category/mode with A2DP allowed and built-in input
  preferred only during recording preparation/recording.
- Remove transient and project-load input prewarming in V2.
- Read actual sample rate, IO buffer duration, route, and channels after session
  activation.
- Close input and restore playback category after recording.
- Generation-protect every asynchronous operation and observer callback.
- Fall back safely to system output/speaker on disconnect.

The reported Bluetooth-disconnect crash must be captured before behavioral
changes so its stack and lifecycle timing can be compared after the fix.

### macOS

- Classify output using Core Audio transport metadata, with name heuristics only
  as a fallback.
- Preserve playback-only startup and existing aggregate-device avoidance.
- Keep Bluetooth input disabled initially.
- Remove project-load input prewarming in V2.
- Select a safe native input immediately before recording preparation.
- Do not automatically create aggregate/combiner devices.
- Apply only values supported by the resulting device and read them back.
- Observe default/selected output changes and route them through the single V2
  coordinator.

## Legacy and V2 coexistence

- Legacy behavior stays intact except separately approved crash-safety changes
  required to keep A/B builds usable.
- V2 code is isolated behind an internal/testing build guard.
- A persisted `Legacy` / `Bluetooth 2.0` selector is shown only in audio
  diagnostics/internal settings.
- Legacy remains the default throughout development and hardware validation.
- Selection is read before editor/engine initialization.
- Changing selection requires reopening the editor/engine.
- Exactly one implementation owns route events and commands per session.
- V2 must not invoke Legacy delayed repair, polling, or prewarm paths.
- Diagnostic logs identify implementation, platform, generation, transition
  ID, and intent.
- Legacy remains available until a later explicit removal decision.

## Failure model and diagnostic codes

Minimum stable diagnostic codes:

- `stale_generation`
- `route_removed`
- `no_output`
- `no_safe_input`
- `bluetooth_duplex_forbidden`
- `unsupported_rate`
- `unsupported_buffer`
- `platform_session_failed`
- `juce_reopen_failed`
- `actual_state_mismatch`
- `fallback_succeeded`
- `fallback_failed`
- `transition_timeout`
- `coordinator_disposed`

Failure UI should say what the user can do. It should never claim success,
silently continue in call-quality output, or hide that simultaneous playback
was muted.

## Delivery plan with approval gates

Each phase is intentionally small. Finishing one phase produces evidence for
the next; it does not automatically authorize the next phase.

### Phase 0 — Review and freeze this specification

Scope: documentation only.

Deliverables:

- approve product invariants and non-goals;
- approve the cross-platform behavior table;
- approve the initial no-Bluetooth-microphone policy;
- identify representative devices/headsets and an owner for physical testing;
- define where diagnostic captures and crash reports will be stored; and
- record unresolved questions rather than guessing.

Exit gate: written approval to begin read-only diagnostics. No production code
changes before this gate.

### Phase 1 — Dormant shared V2 foundation

Scope: shared types and pure logic only; no editor or native behavior change.

Deliverables:

- define route types, snapshots, desired configuration, and diagnostics
  contracts;
- implement pure `AudioRoutePolicyV2`;
- define a read-only snapshot-provider boundary and privacy-safe report
  serializer;
- prove parsing, unavailable-value handling, policy invariants, and report
  redaction;
- do not implement a coordinator, apply interface, transition engine, build
  guard, or usable V2 selector yet.

Automated checks: policy, parsing, nullability, and redaction tests.

Exit gate: shared design is understandable in isolation and Legacy runtime is
unchanged. Completed by commit `c780dfe7`.

### Phase 2 — macOS read-only evidence adapter

Scope: observation only; no route behavior changes.

The first implementation platform is macOS because real Mac hardware is
available. The manual Legacy baseline is intentionally waived rather than
spending testing effort on behavior already known to be unreliable. Commit
`c780dfe7` remains the immutable, buildable Legacy reference if a baseline is
needed later. The iOS disconnect-crash reproduction is deferred until affected
iPhone or iPad hardware is available.

Deliverables:

- add one macOS-only, read-only route snapshot from Core Audio and JUCE;
- expose a debug-only redacted report-copy action;
- report actual rate, buffer, input-open state, stable route identity,
  transport evidence, callback timing, and explicit unavailable reasons;
- tag reports as Legacy; and
- make unsupported platforms return an unavailable snapshot without native
  route calls.

Automated checks: contract parsing, platform isolation, redaction, macOS build,
and repeated real native capture without JUCE configuration changes.

Exit gate: the evidence path is read-only, privacy-safe, and useful enough to
design the first macOS V2 playback slice. Bluetooth-specific audible testing is
deferred until that playback candidate exists.

### Phase 3 — Dual-path scaffolding without Bluetooth behavior

Scope: establish isolation and selection mechanics.

Deliverables:

- persisted internal selector with Legacy default and reopen requirement;
- session-fixed implementation ownership;
- method/event contract plumbing using fake or unavailable V2 adapters;
- diagnostics clearly showing which implementation is active; and
- isolation tests proving V2 cannot call Legacy repair paths and vice versa.

V2 must remain marked unavailable on platforms without a completed adapter.

Exit gate: switching sessions is safe, deterministic, and cannot affect
production/default Legacy behavior. Completed by commit `bcf595d3`.

### Phase 3A — First active macOS playback-startup slice

Scope: initialize playback against the output that already exists when the
editor opens. Do not react to later route changes.

Deliverables:

- independently open JUCE with the current/default Core Audio output and zero
  input channels;
- use route-native hardware settings instead of user hardware overrides;
- validate the actual output identity, rate, buffer, channels, and input-closed
  state before reporting success;
- refuse playback if the verified startup route has changed and require an
  editor reopen;
- prevent Legacy and V2 engine ownership from overlapping; and
- fail closed without falling through to Legacy, retrying, observing routes, or
  changing devices.

Exit gate: built-in output passes native lifecycle tests; the physically
connected Bluetooth headset passes the same startup and playback checks; V2
never opens an input or invokes Legacy repair/prewarm behavior. Completed by
commit `3606fa59`.

Manual WH-1000XM5 evidence on 2026-08-08 confirmed clean 44.1 kHz playback with
a 512-frame hardware buffer, zero active JUCE input channels, no microphone-use
indicator, no callback overruns, and stable coexistence with Spotify. Legacy
opened one input channel and lost output after Spotify paused; V2 did not.

### Phase 4 — macOS V2 live playback consistency

Scope: macOS playback and route changes only; no recording.

Deliverables:

- observe only effective Core Audio default-output, inventory, and active-device
  availability changes;
- immediately pause transport and invalidate a removed output;
- serialize the newest native generation through `AudioRouteCoordinatorV2`;
- reopen the system output with zero inputs and verified native settings;
- attempt at most one unique built-in-output fallback; and
- keep playback paused until the user deliberately resumes.

The active macOS checkpoint uses these stable diagnostic codes: `ok`,
`implementation_conflict`, `stale_generation`, `no_output`, `route_unstable`,
`input_open`, `actual_state_unavailable`, `juce_open_failed`,
`fallback_succeeded`, `fallback_failed`, and `coordinator_disposed`. Broader
cross-platform codes above remain reserved for later phases.

The initial WH-1000XM5 live-switching gate passed on 2026-08-09 after startup
and transitions were consolidated onto one explicit output-only device open.
Repeated speaker ↔ Bluetooth changes caused no headset reset or audible
artifact. Changing output during playback paused the project, preserved the
route transition, and resumed on the selected device only after user action.

Exit gate: stable repeated Bluetooth → local → Bluetooth transitions on the
available Mac, followed by broader Intel and Apple Silicon validation later.

### Phase 5 — Android V2 playback stability

Scope: Android playback only; no recording.

Foundation status (2026-08-10): the branch is based directly on current
`origin/main`, including the original PRO-9 MIDI work. On a Samsung SM-S918N
with Bluetooth disconnected, both Legacy and V2 passed the same on-device meter
suite for Upright Piano preview and timeline playback, a second MIDI row, Basic
Synth, sampled round-robin notes, and live MIDI note-on/off. V2 opened the
system-selected output at the accepted 48 kHz rate and 1920-frame buffer with
two active outputs, zero active inputs, and an attached callback. A normal-app
manual gate confirmed correct project rendering and working audio, MIDI,
transport, metronome, and effects in both implementations, with no microphone
activation, false route-change notice, silence, or crash.

This evidence validates the generic output-only engine foundation. It does not
yet validate Bluetooth routing, Bluetooth rate/buffer behavior, or live route
changes on Android.

Preconnected Bluetooth checkpoint design (2026-08-10): Android resolves the
media output by native device ID, using the media-attributes route on API 33+
and one unambiguous active A2DP endpoint on API 29–32. SCO is rejected. A2DP
and verified playback-only BLE routes enable one isolated Oboe policy:
output-only shared media/music playback, unspecified/native rate,
`PerformanceMode::None`, and one conservative buffer request bounded by the
stream capacity. Startup reads back the actual routed ID, API, performance and
sharing modes, rate, buffer, capacity, burst size, stream state, and xruns.
Any ambiguous, changed, duplex, non-AAudio, or otherwise unverifiable route is
closed synchronously without retry or Legacy fallback. Built-in V2 and Legacy
retain their existing stream construction.

Preconnected Bluetooth evidence (2026-08-10): on the Samsung SM-S918N, V2
opened the already-selected A2DP output as `bluetoothMedia` with
`MODE_NORMAL`, media/music attributes, AAudio shared `PerformanceMode::None`,
44.1 kHz, a verified 1792-frame buffer and capacity, an 896-frame native
burst, two outputs, zero inputs, no SCO route, and no microphone permission or
activation. After the functional gate and sustained playback, the route and
accepted configuration remained unchanged across 100,329 callbacks. The
stream reported zero xruns; two isolated historical callback-over-budget
events did not recur as xrun growth or audible instability, and the recorded
maximum callback time of 10.998 ms remained below the current 40.635 ms
budget. Audio clips, MIDI preview and timeline playback, combined audio/MIDI,
metronome, effects, seeking, repeated Play/Pause, normal editor activity, and
coexistence with another media application remained clean. The V2 built-in
speaker regression check also passed. The manual Legacy comparison was not
repeated because the Legacy baseline had already passed and this checkpoint's
Legacy isolation remains covered by automated tests.

Android live-output checkpoint implementation (2026-08-10): Android V2 now
uses the existing shared coordinator and its single 100 ms settling window.
Public device and playback callbacks are only change signals; the existing
media-route resolver and the actual Oboe routed device remain the source of
truth. A meaningful effective-output change pauses transport at its current
position, detaches the callback, reopens one system-selected output with zero
inputs while preserving the graph, verifies the accepted route and stream
facts, and waits for explicit user Play. Duplicate fingerprints are ignored,
stale generations cannot publish success, a verified Bluetooth-to-speaker
transition is the only fallback result, and failures wait for a new native
route event. No retry, polling, API fallback, vendor branch, input, automatic
resume, or Legacy repair path was added. Automated resolver, validator,
coordinator, contract, selector, diagnostics, and MIDI-readiness tests pass;
the focused physical connect/disconnect acceptance also passed as recorded
below.

Android live-output evidence (2026-08-10): on the Samsung SM-S918N with Sony
headphones, speaker → Bluetooth, Bluetooth → speaker, stopped transitions,
playing transitions, disconnect/reconnect, and repeated back-and-forth changes
all completed cleanly. Playing transitions paused the project and required
explicit user Play before resuming on the selected output. Audio and MIDI
remained functional, with no microphone activation, call-quality route,
crackle, permanent silence, visual regression, or crash. One apparent failure
to auto-select Bluetooth was reproduced while the headphones were connected
to a Mac through multipoint. The captured Android report consistently showed
the built-in speaker as both the system media endpoint and actual Oboe route;
after removing that external-device conflict, Android selected Bluetooth and
Mixroom followed it reliably. This was not evidence of a missed Mixroom route
transition.

Deliverables:

- A2DP/SCO/LE classification;
- media/normal-mode enforcement;
- route-supported rate and bounded buffer policy;
- actual Oboe/AAudio diagnostics and xrun evidence;
- measured selection of performance mode;
- one supported fallback; and
- Legacy/V2 A/B playback testing under CPU load.

Exit gate: no sustained audible crackling or recurring xrun growth after route
stabilization on the agreed representative devices.

### Phase 6 — iOS V2 playback-only and disconnect safety

Scope: iOS playback and route lifecycle only; no recording.

Deliverables:

- direct route observer and generation invalidation;
- output-only session configuration;
- atomic JUCE reopen and actual-state verification;
- safe speaker/system fallback on disconnect; and
- Legacy/V2 A/B diagnostics for connect/disconnect/background/interruption.

Exit gate: zero crashes in the initial iOS disconnect stress run and no input
open during playback.

### Phase 7 — Intent-driven recording across all platforms

Scope: recording preparation, recording, stop, and failure recovery.

Deliverables:

- remove V2 project-load input prewarming;
- open safe input just in time;
- reject Bluetooth headset microphone selection;
- verify high-quality output after input opens;
- safely mute simultaneous playback or fail if the combination is unsupported;
- finalize recordings safely when a route disappears; and
- close input and restore verified playback after stop.

Exit gate: every platform satisfies the recording gates below without adding
new editor-level platform policy.

### Phase 8 — Complete A/B hardware validation

Run Legacy and V2 with the same build, project, device, headset, actions, and
diagnostic capture. Fix V2 without duplicating coordinator ownership or adding
unbounded recovery.

Exit gate: all release gates pass. Legacy remains default.

### Phase 9 — Controlled rollout

1. Make V2 default in internal builds.
2. Make V2 default in staged test builds.
3. Monitor diagnostics and retain local Legacy rollback.
4. Promote V2 to production default only after explicit approval.

Legacy removal is outside this plan and requires a separate decision.

## Test plan

### Automated tests

- Pure policy tests for every route, intent, and relevant capability.
- Coordinator tests for duplicate events, stale generations, simultaneous
  connect/disconnect, overlapping intents, bounded fallback, timeout, failure
  recovery, shutdown, and late callbacks.
- Contract tests for complete/missing/unknown snapshot fields.
- Input lifecycle tests proving project open is output-only and stop/disarm
  closes input.
- Project-setting tests proving hardware rate changes do not mutate project or
  export rate.
- Legacy/V2 isolation tests.
- Adapter tests with mocked native sequences and configuration failures.
- Recording-file tests for input/output disappearance.

### Hardware scenarios

For both Legacy and V2:

- launch with Bluetooth already connected;
- connect and disconnect while stopped, playing, preparing, and recording;
- reconnect repeatedly and switch Bluetooth → speaker/local → Bluetooth;
- record through built-in/default mic while Bluetooth output is active;
- attempt Bluetooth headset microphone selection;
- stop recording and verify high-quality playback restoration;
- background/resume and platform interruptions;
- change project rate/buffer preferences while Bluetooth is active;
- run 30–60 minute playback under CPU load; and
- repeat record cycles and disconnect during capture.

Coverage groups:

- representative Android manufacturers and supported OS versions;
- representative iPhone and iPad generations;
- Intel and Apple Silicon Macs;
- A2DP headphones/speakers;
- headsets containing microphones; and
- Bluetooth LE devices where available.

### Evidence record

Each run records:

- app build, implementation, platform/OS, device, and headset;
- exact action and timestamp;
- route generation and transition ID;
- native input/output identities and route/profile evidence;
- requested and actual rate/buffer/channels;
- input-open state, platform mode, stream state, and performance mode;
- callback timing and xrun count;
- time to stable/failure;
- audible rating: clean, crackling, low quality, dropout, or silent; and
- crash/incident identifier when applicable.

## Release gates

- Zero crashes across at least 100 connect/disconnect cycles per supported
  platform test group.
- No microphone input open during ordinary editing/playback.
- No persistent HFP/SCO/headset-quality route during normal playback.
- No sustained audible crackling or recurring xrun growth after stabilization.
- Recording succeeds with a verified safe combination or fails before capture.
- Recording files remain valid if input or output disappears.
- High-quality playback is restored after every recording stop.
- Recovery completes within two seconds or enters a clear `failed` state.
- Actual route, profile evidence, rate, buffer, channels, input state, callback
  timing, and xrun data are available in diagnostics.
- Legacy remains functional, selectable, and isolated.

## Migration map

| Current responsibility | V2 decision | Owner |
| --- | --- | --- |
| Android playback-only startup | Reuse after verification | Android adapter/JUCE |
| Android normal-mode/SCO cleanup | Reuse as bounded adapter behavior | Android adapter |
| iOS/macOS input prewarming | Remove from V2 | Intent lifecycle |
| macOS Bluetooth-input rejection | Generalize to all V2 platforms | Shared policy + adapters |
| Editor route refresh/polling | Remove from V2 | Native events + coordinator |
| Delayed post-record repair | Replace with one atomic transition/fallback | Coordinator + adapter |
| Project sample rate | Preserve independently | Project model |
| Hardware rate/buffer | Route-aware request and read-back | Policy + adapter |
| JUCE device reopen | Reuse behind atomic native apply | Native/JUCE adapter |
| Name-only route classification | Replace where metadata exists | Native adapter |
| Legacy repair behavior | Preserve only in Legacy | Legacy path |

## Risks and controls

| Risk | Control |
| --- | --- |
| V2 accidentally affects Legacy | Build guard, session-fixed owner, isolation tests |
| Route-event loop | Compare effective facts, debounce duplicates, one queue |
| Disconnect use-after-free/crash | Generation invalidation before teardown, late-callback tests |
| Bluetooth output falls to HFP/SCO | Keep input closed, verify profile after opening input |
| Buffer tuning becomes device-specific patchwork | Bounded capability-based policy and diagnostic evidence |
| Large all-at-once change | Separate approval/exit gate for every phase |
| Platform behavior diverges | One shared product policy; adapters only translate native mechanics |
| State machine becomes complex | Four states, four intents, one fallback, no recursive recovery |
| Test results are subjective | Pair audible rating with timestamped native diagnostics |

## Open questions to resolve before implementation

1. Which exact Android devices, iOS devices, Macs, and headsets form the minimum
   supported hardware matrix?
2. Which secure location will hold unsanitized iOS crash reports when iOS
   hardware becomes available? Redacted Bluetooth reports are clipboard-only
   by default and may be committed under
   `docs/audio/evidence/bluetooth-v2/reports/`.
3. Is muted playback during unsupported Bluetooth-output recording acceptable,
   or should V2 always fail before recording on that combination?
4. What exact buffer upper bounds are supported and useful on each platform?
5. Which Android Oboe statistics are available through the current JUCE version
   without modifying vendored JUCE code?
6. Does the product have a real explicit input-monitoring intent, or should V2
   omit monitoring entirely in its first release?
7. What is the minimum OS/device support matrix used to judge the two-second
   route-recovery target?

## Official technical references

- [Oboe full guide](https://github.com/google/oboe/blob/master/docs/FullGuide.md)
- [Oboe buffer terminology](https://github.com/google/oboe/wiki/TechNote_BufferTerminology)
- [Android low-latency audio](https://developer.android.com/games/sdk/oboe/low-latency-audio)
- [Android audio device callbacks](https://developer.android.com/reference/android/media/AudioDeviceCallback)
- [Apple route-change guidance](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- [Apple preferred hardware settings](https://developer.apple.com/library/archive/qa/qa1631/_index.html)
- [Apple AVAudioSession route description](https://developer.apple.com/documentation/avfaudio/avaudiosessionroutedescription)

## Immediate next step

Commit the accepted Android live-output checkpoint, then design the first iOS
V2 output-only startup checkpoint. That iOS step should establish isolated,
preconnected Bluetooth playback with no input or prewarming and verified
AVAudioSession/JUCE state. Live iOS connection, disconnection, fallback, and
the known Legacy disconnect crash remain a separate following checkpoint so
startup correctness is proven first. Android recording, monitoring, Bluetooth
input, adaptive buffering, polling, vendor workarounds, and automatic resume
remain deferred.
