# Android input controls

Android V2 keeps its existing System Default mono capture and system routing.
The native `AndroidRecordingChannelPolicyV2` defines the supported range and
exposes it through `getAndroidRecordingInputConfigurationV2`. This is an app
recording capability, not the physical microphone/interface channel inventory.

Both editor input controls display read-only **Input 1 (Mono)** for a valid
track. Saved stereo or higher-channel routes remain visible as unavailable.
**Use Input 1 (Mono)** is the explicit replacement action; it changes the selected
track and schedules autosave. Recording and monitoring reject incompatible
selections. Playback stays available. Replacement is disabled during capture,
route transitions, and recovery.

Idle input identity is **System Default**. Only a current, stable active capture
snapshot with a verified routed input and matching mono stream/device counts may
append the microphone name. Device callbacks notify input status independently
of output fingerprint changes. Refreshes coalesce and discard superseded
results, without preparing capture or reconfiguring playback. Missing device
information stays unknown; a confirmed empty input inventory is reported
separately. Unknown presence allows microphone permission and native preparation.

Native intent preparation, recording start, and prepared-route validation enforce
the same mono selection before normal or Bluetooth capture is accepted. Existing
stream, callback, generation, cancellation, interruption, and cleanup checks
remain in place. Android sample rates, export settings, Bluetooth communication
policy, and macOS/iOS recording behavior are unchanged.

## Verification

The focused Dart input, recording-route, and monitoring suite passes. All 61
Android native policy/route tests pass, and the Android arm64 debug APK builds
successfully. Targeted static analysis reports no errors or new diagnostics.

- Dart policy/UI tests cover exact mono bounds, saved incompatible selections,
  explicit replacement callbacks, track changes, disabled actions, and unknown
  versus absent input information.
- Input-status tests cover verified identity, stream end, removal/reconnection,
  stale generations, invalid snapshots, and the read-only plugin method.
- Existing Android, macOS, iOS, and shared route regression suites are run with
  this change. Native policy tests exercise the exact range and exposed contract.
- Host JVM plugin smoke test cannot load `juce_audio_engine` JNI on macOS;
  retain this as a test-environment limitation rather than a passing check.
- Physical Android checks passed for built-in microphone recording/playback,
  Bluetooth connection and recording, immediate replacement of an incompatible
  saved route, selected-track-only persistence, invalid-selection recording
  rejection with uninterrupted playback, and Bluetooth disconnection recovery.
  Logs confirmed that disconnecting during mono Bluetooth capture closed both
  capture streams, returned the route intent to playback-only, and reopened
  System Default output with no active input channels.

All work is local. No push, PR, or external ticket is authorized.
