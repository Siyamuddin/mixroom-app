# Bluetooth 2.0 Reliability Plan and Technical Specification

## Document status

- Status: the macOS V2 playback and live-output checkpoints are complete. The
  Android Legacy baseline, Android V2 built-in-speaker foundation, and Android
  V2 preconnected Bluetooth media playback have passed their initial
  physical-device gates. Android live-output coordination has also passed its
  focused Samsung/Sony hardware gate. iOS V2 output-only playback, live output
  recovery, disconnect safety, and built-in recording have passed their iPad
  gates. iOS Bluetooth recording is not implemented; two experiments failed
  their gates and were removed.
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

## Current V2 state and iOS ownership decision

The accepted implementation boundary as of 2026-08-13 is:

| Platform | Playback | Live output changes | V2 audio recording |
| --- | --- | --- | --- |
| macOS | Built-in and Bluetooth media verified | Verified | Built-in microphone with built-in or Bluetooth media output verified |
| Android | Built-in and Bluetooth media verified | Verified | Not implemented |
| iOS | Built-in and A2DP verified | Verified, including disconnect recovery | Built-in speaker and built-in microphone verified; Bluetooth output recording rejected before mutation |

Legacy remains the default on every platform. macOS and Android do not require
an audio-session ownership correction. Their working V2 paths receive only
regression coverage while the iOS boundary below is changed.

### Confirmed iOS Bluetooth-recording failure

The failed iOS Bluetooth-recording work exposed one concrete ownership defect,
not a general failure of the iOS playback implementation. The plugin configured
the process-wide `AVAudioSession` category, mode, activation, and preferred
input. JUCE then configured and activated that same session again while opening
its iOS device. JUCE's recording category enabled speaker, HFP, A2DP, and
AirPlay options together, and its iOS 18 activation path synchronously waited
for a temporary Audio Unit callback. The expected HFP route did not settle,
validation failed, and the combined open/restoration work caused an
unacceptable multi-second UI stall.

Moving only the plugin's session setters off the UI thread could not correct
the failure because the conflicting mutation and blocking activation remained
inside JUCE device opening. The unaccepted HFP transaction code was therefore
removed rather than patched with delays or retries.

### Single-owner rule for iOS V2

There must be one product-policy owner and one native mutation executor:

- `AudioRoutePolicyV2` chooses the desired route intent and capabilities.
- `AudioRouteCoordinatorV2` serializes route and intent transitions.
- The JUCE iOS audio backend is the sole executor of V2 `AVAudioSession`
  category, mode, options, activation/deactivation, preferred-input, Audio Unit
  open, and Audio Unit close operations.
- The iOS plugin requests a policy, observes route events, and verifies the
  returned actual state. It must not perform a competing session mutation for
  a JUCE-managed V2 device transition.
- Flutter owns user intent and presentation only.

This is an internal ownership seam, not another coordinator or public state
machine. The first migration supports only `legacyManaged`,
`v2PlaybackOnly`, and `v2BuiltInDuplex`. A future
`v2BluetoothHfpDuplex` policy is forbidden until the accepted playback and
built-in-recording paths pass again under single ownership.

JUCE must retain the session work it legitimately needs for device discovery,
interruption handling, actual hardware facts, and shutdown. The correction
must not make JUCE broadly session-blind. Instead, Mixroom supplies the V2
policy and JUCE applies that policy exactly once in the correct device
lifecycle. Legacy continues through the unmodified JUCE behavior.

## Goals

1. Clean Bluetooth playback without persistent crackling, jitter, or dropouts.
2. Crash-free connect, disconnect, reconnect, background, and interruption
   handling.
3. High-quality media output during ordinary playback; no silent switch to a
   call-quality headset profile.
4. Input closed during ordinary editing and playback.
5. Safe recording with a verified platform-supported input/output combination;
   unsupported Bluetooth combinations fail before capture or session mutation.
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
- Supporting Bluetooth headset microphones before the single-owner iOS and
  equivalent Android recording foundations pass their hardware gates.
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
| Bluetooth headset microphone | Deferred until Android recording foundation | Deferred until a writer-free HFP route gate passes | Rejected; built-in mic is the verified path |
| Recording with Bluetooth output | Not implemented yet | Currently rejected before mutation | Verified with built-in microphone |
| Unsupported duplex combination | Mute simultaneous playback or fail clearly | Mute simultaneous playback or fail clearly | Mute simultaneous playback or fail clearly |
| Disconnect | Quiesce, follow system fallback, verify, remain paused | Quiesce, follow system fallback, verify, remain paused | Quiesce, follow system/default fallback, verify, remain paused |

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
5. Bluetooth headset microphones remain disabled unless a platform-specific,
   separately approved duplex checkpoint passes its hardware gate.
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
| Playback, Bluetooth (profile known or unavailable)/LE | Closed | Use native/unspecified supported rate and read actual | Conservative, bounded, route-supported | Off |
| Preparing/recording with Bluetooth output | Platform-supported verified input; otherwise reject before capture | Verify actual after reopen | Stability-oriented and bounded | Off |
| Preparing/recording without Bluetooth | Selected safe input | Verify actual | Route-supported | Off unless explicitly supported |
| Monitoring without Bluetooth | Selected safe input | Verify actual | Route-supported | Explicit intent only |
| Monitoring with Bluetooth | Unsupported initially | — | — | Off |

There is no universal Bluetooth sample rate or buffer. Adapters request
native/unspecified values where supported, apply only a bounded policy proven
for that platform and route, and record the actual accepted settings. The
verified implementations currently include 44.1 and 48 kHz routes and buffers
that differ by platform. Project/export settings never become hardware-route
settings. A 48 kHz/1024-frame combination may be used as a diagnostic
experiment, but it is not a product default or acceptance requirement.

If xruns grow after stabilization, the native adapter may grow buffering in
native burst-sized steps within the approved bound. It must not repeatedly
reopen a stable route or impose an artificial 300 ms delay.

## Input and profile policy

- Do not prewarm input at project load.
- Request microphone permission without opening an audio input stream.
- Open input immediately before record preparation/count-in, not merely because
  a track exists or the editor is open.
- Prefer only input/output combinations explicitly supported and verified by
  the platform adapter. Current verified recording uses a built-in microphone.
- Never select an input by display-name guessing when native transport metadata
  is available.
- After input opens, verify the complete input/output route and expected
  profile. Ordinary playback must remain on a high-quality media route.
- A future explicit Bluetooth-headset recording intent may temporarily use a
  verified duplex/HFP route with a disclosed quality reduction. An accidental
  duplex route remains a failure.
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
- On an ordinary output change, pause transport and preserve position without
  detaching callbacks, closing the device, or reopening JUCE from the plugin.
- Let JUCE's native iOS route handler perform the single RemoteIO restart, then
  verify the settled route and engine state through the shared coordinator.
- Use an explicit playback category/mode for output-only intent.
- Express V2 session behavior as an internal JUCE policy. JUCE is the sole
  executor of category, mode, options, activation, preferred input, and Audio
  Unit lifecycle for an accepted V2 device transition; the plugin observes and
  verifies but does not repeat those mutations.
- Migrate only the already-proven output-only and built-in-duplex policies
  first. Do not introduce HFP during that migration.
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

### Phase 6 — iOS V2 playback and route safety

Scope: iOS playback only; no recording. This phase is deliberately split into
three checkpoints so route changes are not added before the output-only engine
is proven.

#### Checkpoint 6A — built-in output-only foundation

Implementation status (2026-08-10): implemented and accepted on physical iPad
hardware. Debug iOS builds now use the same session-fixed Legacy/V2 selection
contract as the other supported platforms. V2 configures `AVAudioSession` as
playback/default with the existing
mix-with-other-apps policy, opens JUCE with two outputs and zero inputs, retains
the shared graph and processors, and verifies the actual session, route, JUCE
device, callback, rate, buffer, and channel state before reporting success.
Failure closes the partial engine and deactivates the session without falling
through to Legacy.

The iOS snapshot reads every active AVAudioSession endpoint around one
synchronous JUCE diagnostic read, reports capture consistency, keeps native
and JUCE facts separate, and derives input-open state only from active JUCE
input channels. Reports use the existing redacted per-session serializer. iOS
does not create or call the live route coordinator in this checkpoint.

Exit gate: with Bluetooth disconnected, audio clips, MIDI/instruments,
metronome, effects, seeking, and repeated Play/Pause work through the built-in
output; diagnostics show playback/default, a ready callback, positive actual
rate/buffer, zero active inputs, and no microphone indicator. Legacy must still
work after switching back and reopening.

Physical foundation evidence (2026-08-10, iPad on iOS 26.5): the built-in
speaker route was stable and reported `AVAudioSessionCategoryPlayback`,
`AVAudioSessionModeDefault`, 48 kHz, a 256-frame buffer, two active outputs,
zero inputs, an open JUCE device, and an attached callback. Across 2,629
callbacks the maximum measured callback time was 0.781 ms against a 5.333 ms
budget, with zero callback overruns. The functional project gate passed for
normal audio/MIDI playback and editor operation, with no microphone activation
or observed regression. The initial home-screen termination was confirmed by
the device console as the standard iOS restriction on launching an unattached
Flutter debug build, not a Mixroom crash; the Xcode-attached build ran normally.

#### Checkpoint 6B — preconnected Bluetooth media playback

Use the same proven output-only engine. Add only Bluetooth route/profile
classification, accepted hardware-state verification, and evidence for a
Bluetooth device selected before editor startup. Do not add route observation
or recovery here.

Implementation status (2026-08-10): implemented and accepted on physical iPad
hardware. iOS captures one observable output identity after
configuring playback/default and before opening JUCE, rejects HFP, then requires
the same UID, native port type, and normalized kind after the output-only open.
Play performs the same read-only identity/profile check and never repairs or
reopens the route. The accepted native rate and buffer remain untouched. The
iOS startup codes for this checkpoint are `ok`, `implementation_conflict`,
`no_output`, `input_open`, `bluetooth_duplex_forbidden`, `route_unstable`,
`actual_state_unavailable`, and `juce_open_failed`.

Pre-change A2DP evidence (2026-08-10): the iPad selected
`BluetoothA2DPOutput` before editor startup and remained on the same redacted
endpoint across playback. AVAudioSession remained playback/default at 44.1 kHz
and 256 frames with two outputs and zero inputs. JUCE remained open with its
callback attached. Across 6,916 callbacks there was one isolated over-budget
callback and no audible crackle, jitter, dropout, or quality degradation. This
does not justify buffer or sample-rate tuning.

Post-change A2DP evidence (2026-08-10): the guarded startup selected one stable
`BluetoothA2DPOutput` endpoint at 44.1 kHz and 256 frames, with two outputs,
zero inputs, an open JUCE device, and an attached callback. After playback and
one background/resume cycle, the redacted endpoint token, native port type,
normalized kind, session category/mode, rate, buffer, and channel state were
unchanged. Two of 5,545 callbacks exceeded the realtime budget; the 370.377 ms
maximum coincided with app suspension/resume while the average remained 0.516
ms. This is bounded lifecycle interruption evidence, not sustained callback
pressure, and does not justify route-specific buffering or retry logic. Audio,
MIDI, metronome, effects, seeking, repeated Play/Pause, and playback after
background/resume remained clean. Reopening on the built-in speaker also
passed, with no microphone activation or observed regression.

Exit gate: stable, high-quality preconnected Bluetooth playback with zero
inputs and no headset/call-quality profile.

#### Checkpoint 6C — live route coordination and disconnect safety

Add direct AVAudioSession route observation, generation invalidation, atomic
output reopen, verified system/speaker fallback, and paused transport recovery.
This checkpoint owns the known iOS disconnect crash and includes repeated
connect/disconnect, interruption, and background/resume testing.

Checkpoint 6C.1 is intentionally observation-only. After the editor finishes
loading its project and rows, an iOS V2 session registers one
`AVAudioSessionRouteChangeNotification` observer. It compares a native
output-only fingerprint made from UID, port type, and channel count, ignores
duplicates, and records one monotonically increasing generation and native
reason for each meaningful change. Observation never pauses transport, touches
JUCE, changes AVAudioSession, opens input, or activates the coordinator.
Android and macOS behavior are unchanged.

Initial physical evidence (2026-08-11, iPad on iOS 26.5): the built-in and
A2DP snapshots were individually stable, output-only, and correct at 48 kHz
and 44.1 kHz respectively. Their observation counts both read zero because the
attached device log showed that the editor audio engine shut down between the
two captures and a new V2 engine/observer session started on A2DP; counts are
session-local, so this pair does not verify or disprove notification handling.
The foreground same-editor switch must be repeated without leaving or
reopening the editor.

The repeat same-editor gate passed. The observer reported generation/count
`0` on the built-in speaker, `1` after selecting A2DP, and `2` after returning
to the built-in speaker. The original redacted speaker token returned, and the
disconnect cause was `oldDeviceUnavailable`; the connect notification carried
Apple's truthful `unknown` reason. All three captures were stable and remained
playback/default with two active outputs, zero inputs, an open device, an
attached callback, and zero callback overruns. The attached console showed no
observer-created assertion or crash during these foreground changes.

Powering off Bluetooth while Mixroom was backgrounded reproduced a concrete
debug failure. The attached debugger stopped on the realtime scratch-capacity
assertion at `NativeEffects.h:28` after the route disappeared. This is evidence
for the known disconnect/lifecycle defect and not evidence that the read-only
observer called an audio setter or JUCE lifecycle operation. Release builds do
not stop on JUCE debug assertions, but the oversized callback-block condition
still requires safe quiescing in the following disconnect-safety checkpoint.

Checkpoint 6C.2 adds only that safety boundary. A meaningful iOS output change
pauses native transport, detaches the JUCE callback, and closes the device only
when AVAudioSession reports `oldDeviceUnavailable`. The existing observation
event then reports whether playback had been active and whether the callback
was detached/device closed. Dart invalidates in-flight Play, freezes the UI at
the paused native position, blocks Play and MIDI preview, and requires the
editor to be reopened. There is no device reopen, AVAudioSession mutation,
coordinator activation, retry, fallback, or effect scratch-buffer change in
this checkpoint.

Physical safety evidence (2026-08-11, iPad on iOS 26.5): a stopped
built-in-to-A2DP change produced one generation with the JUCE callback detached,
zero inputs, a responsive editor, a single reopen notice, and blocked Play.
After reopening on A2DP, powering off the headphones during playback paused the
project and produced `oldDeviceUnavailable`; the verified speaker snapshot
showed `deviceOpen: false`, `audioCallbackAttached: false`, and zero active
channels. Repeating the power-off while Mixroom was backgrounded also returned
to a responsive, paused, reopen-required editor. The sole attached Flutter
debug session recorded no `NativeEffects.h:28` assertion, `SIGTRAP`, crash, or
debugger stop. The earlier `SIGKILL` was traced to two competing `flutter run`
install sessions and is excluded from Bluetooth evidence.

Checkpoint 6C.3 replaces the temporary reopen-required path with the existing
shared `AudioRouteCoordinatorV2`. The proven iOS observer remains the only
native route owner and emits the shared generation event after quiescing. The
coordinator starts only after project loading, uses its existing 100 ms
settling window, and requests one atomic output-only reopen. iOS configures
playback/default, accepts the single system-selected output, rejects HFP or
missing identity, opens JUCE once with zero inputs and native rate/buffer, then
validates the route identity, session, device, callback, channels, rate, and
buffer. A system-selected Bluetooth-to-speaker transition is the only fallback
result. Failure closes the partial device and waits for a new route event;
there is no polling, retry, forced route, Legacy repair, or automatic resume.
Physical iPad acceptance remains required before commit.

Physical automatic-recovery evidence (2026-08-11, iPad on iOS 26.5): one
same-editor session completed speaker → A2DP, A2DP → speaker, Bluetooth
power-off during playback, Bluetooth power-off while backgrounded, and five
additional speaker/Bluetooth changes. Generations and transition IDs advanced
monotonically from `1` through `11`. Every captured result was stable,
playback/default, output-only, and callback-attached after recovery. A2DP used
the accepted 44.1 kHz/256-frame configuration; the built-in speaker used 48
kHz/256 frames. No microphone input opened, the single historical callback
overrun did not grow, and the attached console recorded no
`NativeEffects.h:28` assertion, `SIGTRAP`, crash, or debugger stop. Audio and
MIDI resumed only after explicit user Play. A small bounded UI hitch was
visible during each synchronous device replacement; it did not persist or
affect recovered playback and is retained as known transition behavior rather
than adding asynchronous lifecycle complexity. Repeated AudioQueue sample-rate
probe messages (`err = -50`) did not prevent any verified JUCE reopen.

Exit gate: zero crashes in the iOS route-change stress run, no input open during
playback, and deterministic verified recovery or a clear failed state.

### Phase 7 — Intent-driven recording across all platforms

Scope: recording preparation, recording, stop, and failure recovery.

Deliverables:

- remove V2 project-load input prewarming;
- open safe input just in time;
- reject Bluetooth headset microphone selection unless an explicit,
  separately gated duplex-recording policy is active;
- verify high-quality output after input opens;
- safely mute simultaneous playback or fail if the combination is unsupported;
- finalize recordings safely when a route disappears; and
- close input and restore verified playback after stop.

Exit gate: every platform satisfies the recording gates below without adding
new editor-level platform policy.

#### Checkpoint 7A — macOS built-in recording foundation

The first recording checkpoint is intentionally narrower than Bluetooth
recording. With the built-in Mac output selected, V2 remains output-only until
Record is pressed, then the shared coordinator changes intent to
`preparingRecording`. The macOS adapter uniquely resolves a built-in Core
Audio input, opens exactly one input channel alongside the verified output,
and reads the actual JUCE state back before the WAV writer may start.

The writer reuses the existing graph and clip-insertion path but cannot invoke
Legacy device setup or repair. Stop finalizes the WAV before the coordinator
returns to `playbackOnly` and verifies zero inputs. MIDI recording, input
monitoring, external inputs, Bluetooth inputs, and recording on Android/iOS
remain blocked. A meaningful output change during preparation or recording
quiesces and finalizes the session, closes the device, and requires reopening
the editor; automatic record-route recovery is deferred.

Automated contract, coordinator, isolation, and build checks precede a short
physical Mac gate. The checkpoint is committed only after built-in recording,
input closure, clip playback, and Legacy regression checks pass.

Physical acceptance evidence (2026-08-11, Mac built-in output and built-in
microphone): the editor opened in `playbackOnly` with zero active inputs and no
microphone indicator. Microphone permission and the single input were opened
only when Record was pressed. Repeated Record/Stop cycles produced valid,
audible mono clips through the existing graph, and the recording playhead and
growing clip remained visible after the recording transport-readiness fix.
Opening input causes one short, intentional pause while the output-only device
is replaced; no input is kept warm to hide that transition. After Stop, the
verified report returned to `playbackOnly` at 44.1 kHz and 512 frames with the
callback attached, two active outputs, zero active inputs, `inputOpen: false`,
and zero callback-budget overruns. The microphone indicator disappeared.

#### Checkpoint 7B — macOS Bluetooth output with built-in microphone

The next recording combination reuses Checkpoint 7A without adding another
route owner or recovery path. A stable, system-selected classic Bluetooth
output may remain active while the coordinator opens exactly one built-in Mac
input just in time. The native readback must retain the output UID, transport,
and stereo shape, resolve the input as built-in, and report one active input.
Bluetooth input, Bluetooth LE, external input, ambiguous identity, and duplex
output remain unsupported.

JUCE's existing separate Core Audio input/output path selects only a common
native rate and buffer; Mixroom does not create a persistent macOS aggregate
device or impose project hardware settings. Failure restores the same verified
output-only route once. A route change during recording keeps the existing
safe boundary and requires reopening the editor.

Physical acceptance passed on 2026-08-12 with a WF-1000XM5. Playback-only used
the classic Bluetooth stereo output at 44.1 kHz and 512 frames with zero active
inputs, even though macOS exposed the headset microphone separately. Recording
opened only the built-in Mac microphone as one mono input, retained the same
Bluetooth output, kept the callback attached, and recorded a valid mono WAV.
Stop restored the same output at 44.1 kHz and 512 frames with zero inputs and
`inputOpen: false`. Playback remained clean and did not enter call-quality
mode. Repeated Record/Stop, a quick cancellation, and Bluetooth disconnection
during recording all passed; disconnection safely required an editor reopen
without a crash or freeze.

#### Checkpoint 7C — iOS built-in recording foundation

The first iOS recording checkpoint reuses the same coordinator intents and
writer lifecycle with Bluetooth disconnected. A V2 editor remains
`playbackOnly` until Record requests permission. Native code then quiesces the
device, configures AVAudioSession as `playAndRecord`/`default`, selects exactly
one built-in microphone through `setPreferredInput`, and opens JUCE once with
one input and two outputs. The writer may start only after the session, route,
callback, rate, buffer, and active channels are read back and verified.

Stop finalizes the WAV before clearing preferred input, restoring
`playback`/`default`, and reopening output-only JUCE once. Preparation failure
gets one bounded output-only restoration. Route changes during preparation or
recording use the existing safe invalidation boundary and require reopening
the editor. Bluetooth output/input, external input, monitoring, background
recording, and interruption recovery remain outside this checkpoint.

Initial physical evidence (2026-08-12, iPad on iOS 26.5) verified the full
built-in route lifecycle. Playback-only used the speaker at 48 kHz and 256
frames with zero inputs. Recording used `playAndRecord`/`default`, the built-in
microphone as one mono input, the same built-in speaker as two outputs, and an
attached callback. The first hardware run exposed an incorrect teardown order:
the session was changed while the input device remained open, leaving the
engine closed after Stop. Reordering teardown to finalize, detach and close,
clear preferred input, restore `playback`/`default`, and reopen output-only
resolved it. Repeated recording then succeeded without reopening the editor;
the final report showed `playbackOnly`, zero inputs, `inputOpen: false`, and an
attached 48 kHz/256-frame output callback. Recording-start cancellation and a
Legacy Record/Stop regression check also passed.

#### Checkpoint 7D evidence — iOS Bluetooth recording deferred

Two bounded Bluetooth-recording experiments failed their physical iPad gate.
A2DP output plus the built-in microphone changed the duplex engine to a 16 kHz
one-input/one-output route and blocked the editor while opening and restoring
audio. A subsequent classic-Bluetooth transaction explicitly selected the
headset HFP input by native port identity, but iOS still did not establish a
usable duplex route before JUCE validation and the system transition produced
an unacceptable multi-second UI stall. Moving AVAudioSession mutation to a
private serial lane and correcting a stale route-read boundary did not make the
hardware behavior acceptable.

The unaccepted HFP implementation was removed in full. iOS V2 retains the
proven output-only A2DP playback, live switching, disconnect safety, and
built-in speaker/microphone recording paths. When A2DP is the active output,
Record now fails immediately after one read-only snapshot and before requesting
permission or changing AVAudioSession/JUCE. No forced rate, delay, retry,
polling, device-name match, or headset-specific workaround was added.

#### Checkpoint 7E evidence — iOS V2 session-ownership correction

This checkpoint changes no user-facing capability. It introduces one narrow
policy seam in the vendored JUCE iOS backend and migrates only the accepted
`v2PlaybackOnly` and `v2BuiltInDuplex` paths. The plugin stops independently
setting category, mode, activation, preferred input, or deactivation for those
JUCE device transitions. JUCE applies the requested V2 policy once, opens or
closes its Audio Unit, and exposes actual state for the existing plugin
verification. Legacy retains its current JUCE-managed behavior.

The migration must preserve output-only speaker/A2DP playback, live route
switching, disconnect recovery, background/resume, built-in recording,
repeated Record/Stop, graph contents, transport position, and zero inputs
outside recording. It adds no HFP route, recording-writer change, coordinator
state, retry, polling, delay, buffer tuning, Android behavior, or macOS
behavior. JUCE's iOS 18 compatibility activation may remain, but a V2
transition must not activate redundantly; activation count and transition
elapsed time are verified in tests and on hardware.

The iPad gate passed on 2026-08-13 for built-in playback, A2DP playback,
speaker/A2DP switching, background/resume, built-in Record/Stop and recording
cancellation. A2DP Record remained an immediate read-only rejection with no
permission request, microphone activation, route mutation, or freeze.

#### Checkpoint 7F evidence — JUCE-owned ordinary route recovery

The remaining disconnect assertion came from two recovery owners reacting to
one physical iOS route change: JUCE's native route handler restarted RemoteIO
while the Mixroom observer detached/closed it and the coordinator reopened it
again. The temporary `deviceCallbackActive` workaround and effect stack logger
did not correct that ownership conflict and were removed.

Ordinary iOS route recovery now has one mutation owner. The Mixroom observer
only records whether transport was playing, pauses at the preserved position,
increments the native generation, and emits the route event. The coordinator's
iOS apply is verification-only: after the existing 100 ms settling window it
requires the event fingerprint, current AVAudioSession output, JUCE callback,
channels, rate, buffer, and zero-input state to agree. It performs no callback
detach, device close/open, AVAudioSession mutation, retry, polling, or delay.
JUCE alone performs its built-in iOS RemoteIO route restart.

The physical iPad gate passed three Bluetooth-disconnect cycles during
playback without the prior `NativeEffects.h:28` assertion, freeze, crash, or
microphone activation. Every cycle paused Mixroom, preserved position,
recovered the system-selected speaker, and resumed only after user action.
Background/resume passed on speaker and A2DP. Built-in Record/Stop passed three
times plus cancellation. Final reports verified:

- speaker: stable `playback/default`, 48 kHz, 256 frames, attached callback,
  two outputs, zero inputs, and `inputOpen: false`;
- A2DP: stable `playback/default`, 44.1 kHz, 256 frames, attached callback,
  two outputs, zero inputs, and `inputOpen: false`.

Route invalidation during iOS recording now owns terminal cleanup: it stops the
writer and monitoring, shuts down V2 once, preserves project/transport state,
and requires reopening the editor. It does not attempt playback restoration
from the invalidated recording-abort path. Ordinary recording Stop continues
to use the explicit output-only restoration path.

After this checkpoint, the next separate experiment is writer-free:
open a verified A2DP route, transition once to verified HFP duplex, immediately
close it, and restore the exact original A2DP identity. Recording and clip
insertion remain disabled until that route-only experiment is responsive,
cancellable, and repeatable on hardware.

#### Checkpoint 7G — writer-free iOS HFP duplex proof

The next implementation isolates the only unproven iOS recording primitive
from the writer and recording UI. A debug-only probe starts on one verified
A2DP output, asks the JUCE-owned session policy for exactly one observable HFP
input, verifies the resulting HFP input/output route and active callback, then
immediately restores the exact original A2DP endpoint with zero inputs.

JUCE remains the sole executor of AVAudioSession and Audio Unit mutations. The
plugin owns only a bounded source/target operation record and actual-state
verification. Notifications are consumed as intentional only when the complete
input/output fingerprint matches the operation's exact source or verified
target; disconnects, interruptions, missing routes, and unrelated routes retain
the normal failure boundary. There is no writer, monitoring, retry, polling,
delay, forced rate, fixed buffer, or device-name matching in this checkpoint.
Ordinary A2DP Record remains an immediate read-only rejection.

On iOS 26.5 hardware, the public category-options readback normalized to
`mixWithOthers` after the explicitly configured HFP input was selected, while
the actual route contained one HFP input and one HFP output. Validation therefore
requires the successful JUCE HFP policy result and the complete actual HFP
route. It still rejects A2DP-recording and default-speaker options during the
duplex phase; the normalized absence of the enabling bit is not treated as a
route failure after HFP has demonstrably become active.

The physical gate requires five responsive A2DP → HFP → exact A2DP round trips,
one cancellation, and one disconnect failure. Until that gate passes, HFP is a
diagnostic capability only and Bluetooth recording remains unsupported.

Five ordinary round trips passed on the iPad, proving the JUCE-owned transition
from stereo A2DP to native mono HFP duplex and back to the exact source A2DP
identity. Removing the headset during the probe exposed a separate callback
admission race: a transitional callback could reach graph effects after the
device stop had cleared its prepared block and channel facts, producing the
`NativeEffects.h:28` assertion.

The disconnect-safety boundary therefore lives at the shared JUCE callback, not
inside effects or Bluetooth timing. A callback is admitted only after device and
graph preparation publishes an exact block capacity and channel shape; teardown
closes that gate before stopping the player. Invalid or stale callbacks clear
available output and return before capture, transport, graph, effects, meters,
metronome, or writer work. Physical removal or interruption also marks the
one-shot intent terminal before main-thread observation, so the probe closes the
partial engine and requires an editor reopen instead of forcing A2DP restoration.
No retry, delay, polling, scratch-buffer enlargement, or callback-thread device
operation is introduced. Post-correction disconnect evidence remains pending the
physical iPad gate.

#### Checkpoint 7H — asynchronous single-owner duplex lifecycle

The remaining disconnect freeze was traced to explicit AVAudioSession and JUCE
device transitions executing inside Flutter's platform-thread method handler.
The writer-free proof now uses one private serial iOS lifecycle lane. Flutter
receives the result asynchronously, while ordinary iOS output changes remain
owned by JUCE's native route handling.

The operation retains its exact A2DP source, coordinator generation, complete
route fingerprints, lifecycle phase, and one cleanup claim. A matching HFP
route notification can wake the transition without polling. Physical removal,
interruption, missing routes, and unrelated routes atomically invalidate the
operation and close it without forcing A2DP restoration. Ordinary validation
failure may restore the exact source once. Abort and shutdown serialize behind
the same owner, so late native work cannot race disposal.

HFP readiness now requires at least one valid callback with the prepared mono
input/output shape; `audioDeviceAboutToStart` alone is not accepted. A one-second
event wait bounds callback proof, and one two-second operation deadline only
terminates an uncompleted check—it never retries or initiates recovery. Reports
remain schema-version 1 and add nullable phase, callback-count, terminal-cause,
and cleanup-outcome evidence. Bluetooth recording and the realtime WAV writer
remain disconnected from this proof.

#### Checkpoint 7I — recording-route disconnect recovery

The accepted HFP recording path now follows an `oldDeviceUnavailable` event with
one serialized transition to `playbackOnly` after the invalidated recording
intent has completely stopped. The native owner discards unpublished capture,
ends HFP transaction ownership, accepts the single non-HFP output selected by
iOS, and verifies `playback/default`, zero inputs, an attached callback, and
positive native rate and buffer. It does not force speaker or A2DP routing and
does not retry.

Physical iPad testing passed both removal during recording preparation and
removal during active recording. In each case the unpublished take was not
inserted, the microphone closed, the editor remained responsive, and playback
continued through the replacement system output after manual Play without
reopening the editor. If this single verification or reopen fails, the existing
terminal shutdown and editor-reopen boundary remains the fallback.

#### Checkpoint 7J — system-selected recording-route proof

The next iOS checkpoint removes Mixroom's input choice from a writer-free
route experiment. A private `v2SystemSelectedDuplex` JUCE policy configures
`playAndRecord/default` with the standard speaker, A2DP, and HFP capabilities,
then activates without calling `setPreferredInput` or matching device names.
iOS chooses the active input and output; Mixroom accepts the result only after
one observable input, one observable output, the complete route fingerprint,
active channels, native rate/buffer, and a real project callback all agree.

The experiment reuses the existing lifecycle executor, two-second deadline,
observer transaction, callback gate, and exactly-once cleanup. It records and
monitors nothing, never starts transport, and restores the exact source output
with zero inputs immediately after verification. An unchanged output is
accepted for built-in, wired/USB, or built-in-microphone-plus-A2DP routes. An
A2DP source may also become a verified HFP input/output pair because iOS couples
that profile intentionally. Any other output change, removal, interruption,
missing identity, stale generation, or unstable route fails safely.

Reports remain schema-version 1 and identify this debug evidence with
`selectionMode: systemSelected`. The physical gate requires repeatable built-in
and microphone-equipped-headset results, plus a genuine A2DP-only speaker before
built-in-microphone-plus-A2DP support can be claimed. Production Record behavior
is unchanged until this route-only gate passes.

On the built-in iPad route, iOS established and JUCE verified the requested
built-in microphone plus speaker route at 48 kHz/256 frames with one valid
project callback, but the public category-options readback normalized the
configured speaker/A2DP/HFP capability set to `mixWithOthers` plus
`allowBluetoothA2DP`. The probe therefore treats the successful JUCE policy
result as evidence of the requested options and the complete active route as
evidence of iOS's selection. It retains the normalized options in diagnostics
but does not require iOS to echo every configured capability bit.

The physical iPad route gate passed five times for each required route class:

- built-in microphone plus built-in speaker at 48 kHz/256 frames;
- headset HFP input/output from an A2DP source, followed by exact 44.1 kHz
  A2DP restoration; and
- built-in microphone plus the unchanged microphone-less A2DP speaker at
  44.1 kHz/256 frames.

Every accepted check completed a real project callback and restored
output-only playback with zero inputs. The representative microphone-less
speaker check completed in 564 ms with no callback overrun. Physical headset
removal during a check entered the intended terminal editor-reopen boundary
instead of forcing restoration. Actual recording through the system-selected
route remains outside this writer-free checkpoint.

#### Checkpoint 7K — system-selected recording integration

Production iOS V2 recording now reuses the accepted system-selected duplex
operation instead of choosing separate built-in and HFP preparation paths.
One private intent-operation mode distinguishes the writer-free diagnostic from
real recording without adding a coordinator state or MethodChannel method.
JUCE configures `playAndRecord/default` with the existing speaker, A2DP, and HFP
capabilities and never selects an input or matches a device name. iOS chooses
the complete route; Mixroom requires the exact verified input/output
fingerprint, one real project callback, active channels, and positive native
rate/buffer before admitting realtime-safe WAV capture.

The same production path accepts the three physically proven route classes:
built-in microphone plus speaker, HFP headset input/output from an A2DP source,
and built-in microphone plus an unchanged microphone-less A2DP speaker. The
reduced-quality notice is based on the verified HFP target rather than the
source being Bluetooth, so A2DP plus built-in input is not mislabeled. Ordinary
Stop finalizes capture before restoring and verifying the exact original
output-only route. Existing cancellation, removal recovery, and terminal
reopen boundaries remain unchanged.

The physical iPad recording gate passed for all three required route classes:

- built-in microphone plus speaker recorded repeated short and 30-second takes
  at 48 kHz/256 frames and restored output-only playback;
- a microphone-equipped headset recorded through verified 16 kHz/256-frame
  mono HFP input/output and restored the exact original 44.1 kHz A2DP output;
- a microphone-less A2DP speaker remained the two-channel output while iOS
  selected the built-in microphone at 48 kHz/256 frames, with no HFP-quality
  warning.

Successful takes were audible, cancellation published no clip, and the
microphone closed after every Stop. Physical removal during preparation entered
the existing safe reopen boundary. Physical removal during active HFP recording
discarded the interrupted take and recovered a 48 kHz output-only built-in
route with zero inputs. The editor remained responsive and the attached logs
contained no assertion, crash, callback failure, or microphone leak. Playback
after a terminal invalidation now reports the existing reopen requirement
directly instead of presenting a generic unavailable-output message.

#### Checkpoint 7L — interruption and foreground recovery

iOS V2 now treats calls, Siri, alarms, suspension, and foreground return as one
bounded interruption episode. Native observation distinguishes interruption
begin and end, records the suspension/reason/resume-hint facts for diagnostics,
and emits terminal events even when the output fingerprint is unchanged. Begin
only pauses and invalidates; it never activates or reopens audio. End, or one
native foreground reconciliation after a real background event, permits one
serialized output-only recovery through the existing lifecycle executor and
coordinator.

Recording preparation and active recording share the same cleanup owner:
capture admission closes, unpublished audio is discarded, input/duplex audio
closes once, visuals stop, and no clip is inserted. Playback restoration then
uses the current iOS-selected output rather than the pre-interruption route and
requires playback/default, zero inputs, an attached callback, active outputs,
and positive native settings. Playback and recording remain paused until the
user acts. Duplicate and late notifications cannot start a second cleanup or
reopen, and repeated background/foreground episodes on an unchanged route each
perform a real recovery instead of reusing an earlier result.

The schema-version 1 report adds optional interruption phase, suspension,
reason, resume-hint, and recovery-outcome facts. The automated coordinator,
observer, recording, HFP, redaction, and engine suites pass, as do iOS, Android,
and macOS debug builds. The physical iPad gate passed Siri interruption on
speaker and A2DP playback, interruption of built-in and HFP recording,
background cancellation during HFP recording, and stopped foreground recovery
on speaker and A2DP. Each path remained paused, closed the microphone, preserved
the project, and permitted manual playback or another recording afterward.

The first background-recording run exposed a JUCE RemoteIO lifetime race: a
stream-format property callback could reach its device owner while the Audio
Unit was being disposed. The tracked JUCE patch now unregisters and drains that
listener, stops RemoteIO before disposal, and rejects notifications for an
owner that is no longer live. Rebuilt device and simulator archives passed the
same hardware case without a crash or freeze.

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
| iOS plugin and JUCE both mutate `AVAudioSession` | One V2 policy request; JUCE is the only device-transition mutation executor |
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
3. Which future recording combinations should be exposed after their separate
   hardware gates: A2DP plus built-in input, HFP duplex, or both?
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
- [Apple AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Apple preferred input](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferredinput(_:))
- [Apple A2DP category option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp)
- [JUCE iOS audio backend](https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_devices/native/juce_Audio_ios.cpp)

## Repository hygiene for the next checkpoint

- Generated `ios/Podfile.lock` checksum churn from local build/install work is
  unrelated to Bluetooth behavior and must not be included in the checkpoint.
- Existing unrelated engineering-document changes remain user-owned and are
  not modified or bundled with Bluetooth work.
- The session-ownership correction is reviewed and committed independently
  only after its existing-behavior hardware gate passes.

## Immediate next step

Begin the Android V2 recording foundation while retaining the completed iOS
cross-route regression gate as the non-regression baseline. Mobile selectors
remain a separate product decision.
