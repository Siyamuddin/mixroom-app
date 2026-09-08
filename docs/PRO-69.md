# PRO-69 — macOS output sample rate

On macOS, opening a project, changing outputs, returning from capture, and
buffer-only changes follow the active output's current CoreAudio clock. Saved
`ui.sampleRate` remains compatible project metadata, not an automatic hardware
request. Explicit manual rate edits still use the existing serialized route
configuration and native recovery. Detected rates are not limited to UI presets.

The existing configuration API accepts `preferredSampleRateHz: 0` on macOS to
preserve the output clock. Automatic operations, including buffer rollback, do
not call the CoreAudio sample-rate setter. Native reopens use fresh inventory;
route generations and callback/graph verification continue to govern admission.
Other platforms retain their existing rate policy.

## Verification

Run the focused hardware integration suite on a macOS output supporting 44.1 and
48 kHz and 256/512-frame buffers:

```
flutter test --no-pub -d macos integration_test/daw_sample_rate_macos_test.dart
```

The project test uses isolated temporary project files, observes actual native
requests, loads 44.1 kHz audio, checks the project-settings value, and verifies a
brief quiet signal reaches the output meter. It also records briefly through
the current microphone and checks the displayed clock after recording recovery. Set the output to 48 kHz in Audio
MIDI Setup before running to reproduce the studio mismatch. Repeat at 44.1 kHz.
The native settings test exercises both rates, buffer-only updates, and rejected
requests; it restores its starting rate and buffer afterward.

Manual acceptance checks:

- Open a saved project on built-in speakers at 44.1 and 48 kHz. Confirm automatic
  project settings and normal audible playback at each rate.
- Change the output rate externally while the DAW is open. After recovery,
  hardware, device, graph, and displayed rates must agree. Playback may pause;
  press Play again.
- Connect/select Bluetooth earbuds, play, disconnect, and play through speakers.
  Repeat with the built-in microphone selected for recording, then return to
  playback. Verify normal audio and consistent clocks after each transition.
- After merge, the studio must verify the original project automatically opens
  at its interface's 48 kHz rate and produces sound. This remains pending until
  studio confirmation; local tests do not substitute for that check.

## Separate input-channel follow-up

Use actual selected/default input capacity for mono and adjacent stereo choices;
handle input-only device changes and saved selections unavailable on a smaller
interface. The existing capacity calculation can inflate the menu using saved
routing. Changing only that calculation would leave device lifecycle and
unavailable-selection behavior unresolved. No input-menu changes belong to this
PR.

## Implementation check results

- Focused Dart/native-contract regression suite: 203 passed.
- macOS debug build: passed (existing native compiler warnings).
- Changed helper/coordinator/test analysis: no issues. Editor analysis: no errors
  and no diagnostics on changed lines; existing warnings and lints remain.
- Real project-open/settings/audio-meter integration: passed at 48 kHz with
  saved 44.1 kHz settings, and at 44.1 kHz with saved 48 kHz settings.
- Native hardware integration: passed manual 44.1/48 kHz changes, automatic
  buffer-only changes, invalid-rate rejection, and original-settings restoration.
- Human checks confirmed normal speaker playback, live 44.1-to-48 kHz changes,
  Bluetooth playback, and built-in microphone recording/playback. Logs verified
  earbuds at 44.1 kHz and recovery to speakers at 48 kHz, with no reported overruns.
- Recording exposed a missing UI update after native recovery. The real editor
  regression reproduced it before the fix and passed afterward; accepted
  recording/monitoring transitions now publish their verified rate to settings.
- Studio acceptance on the original interface remains pending after merge.

## Device-supported sample-rate control

On macOS, output snapshots include the driver's valid nominal-rate ranges and
whether manual changes are supported. Writable outputs offer reported discrete
rates, plus supported common rates and integer boundaries for continuous ranges.
The verified current rate stays visible even when it is not an editable choice.
Missing capabilities, a single available rate, and Bluetooth outputs use a
read-only value. Bluetooth rate/profile changes remain controlled by macOS;
external changes still update the DAW. Native requests revalidate hardware
availability and reject unsupported explicit Bluetooth changes. No other-platform
rate policy or input-channel selection behavior is changed.

Capability tests cover discrete and continuous ranges, invalid/missing metadata,
read-only outputs, rates outside presets, serialization, and exact display labels.
All three macOS integration tests passed on built-in speakers after this change,
including the actual settings menu. Static analysis found no errors or helper/test
diagnostics; existing editor warnings/lints remain. The user confirmed the Bluetooth read-only UI and audible playback on this
revised build. Monitoring captured repeated 44.1 kHz stereo → 16 kHz mono →
44.1 kHz stereo transitions with matching hardware/device/graph clocks, attached
callbacks, and zero reported callback overruns (2026-09-08).

## Final review (2026-09-08)

- Audited macOS playback-open and hardware-configuration call sites. Automatic
  opens use the current output inventory; only explicit requests may settle a
  different nominal rate. Automatic rollback retains the current clock.
- Reviewed generation checks, output identity validation, callback admission,
  and recording/monitoring recovery. Existing coordinator tests cover failure,
  interruption, cancellation, and stale-event serialization; these are not
  substitutes for fault injection on every physical interface.
- Source timing remains in seconds with source-rate-to-device-rate resampling.
  The playback graph is prepared for the admitted device rate. Normal exports
  retain their independent export settings and offline graph rate.
- Expanded regression run: 214 passed, one failed, six skipped. The failing
  `audio_export_plan_test.dart` MP3 dithering/filter expectation and its helper
  are identical to current `origin/main`; PRO-69 changes neither. The six host
  export matrix tests are explicitly skipped by their existing configuration.
  The focused PRO-69 suite remains 203 passing checks.
- Latest main adds unrelated track-header interaction changes; no overlapping
  files with this fix. No further PRO-69 implementation blockers found.
- Input-channel discovery is specified above but has no separate tracker issue
  yet. Studio acceptance remains pending after merge.
