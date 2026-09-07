# iOS monitoring and recording verification (PRO-72)

The iOS V2 capture lifecycle preserves an already-enabled, verified monitoring
route. The take may target another row, but its input channels must match the
monitor. Monitoring keeps its original row, channels and device-stream generation.
Bluetooth monitoring and new route configurations remain outside this change.

## Automated verification

From the repository root:

```sh
python3 tool/test_ios_capture_lifecycle.py
flutter test test/live_input_monitoring_v2_contract_test.dart test/realtime_wav_capture_contract_test.dart test/ios_bluetooth_v2_recording_contract_test.dart test/ios_bluetooth_v2_observer_contract_test.dart test/ios_audio_session_policy_contract_test.dart test/ios_audio_interruption_v2_contract_test.dart test/ios_bluetooth_hfp_duplex_probe_contract_test.dart test/ios_system_selected_recording_route_probe_contract_test.dart test/macos_bluetooth_v2_recording_contract_test.dart test/android_bluetooth_v2_recording_contract_test.dart juce_audio_engine/test/audio_route_coordinator_v2_test.dart
android/gradlew -p android :juce_audio_engine:testDebugUnitTest --tests '*Android*Test'
flutter build ios --debug --no-codesign
flutter build macos --debug
python3 tool/test_macos_monitor_capture.py
python3 tool/test_android_monitor_capture.py --juce-library build/macos/Build/Products/Debug/juce_audio_engine/juce_audio_engine.framework/Versions/A/juce_audio_engine
```

The Foundation host test executes the production capture helper with an injected
native bridge. It exercises duplicate starts, exact mono/stereo channel selection,
monitor-target/connection/stream-generation mismatches, repeated takes, writer
failures, cancellation before/during/after start, stale start/stop/delivery, and
replacement ownership. Fake hooks control when cancellation or invalidation
arrives; the test checks that capture-only cleanup leaves the monitor intact and
never restores an invalidated monitor or touches replacement capture.

The host runner also compiles the plugin's actual capture-start reply expression
and verifies that every success/failure combination produces a Core Foundation
boolean. Boxing a C logical expression directly produces an integer instead,
which violates Dart's `invokeMethod<bool>` contract. This regression failed before
the explicit `@YES`/`@NO` fix and passed afterward.

The host does not execute AVAudioSession or the entire Flutter plugin. Source
contracts verify plugin dispatch, capture-only bridge wiring, read-only graph
verification and shared Dart preflight. The existing graph/WAV signal test
(despite its Android filename) exercises the JUCE graph and shared production
WAV writer used by both platforms, including mono/stereo, repeated takes,
cancellation, writer failure and monitoring-off output. It does not execute the
iOS callback wrapper or a physical iPhone audio route. These checks support, and
do not replace, hardware listening acceptance.

## User-performed iPhone acceptance

Before installation, verify signing/application identity. Never uninstall the
existing app or clear its data to resolve installation failure without explicit
user approval. An unsigned build is not ready for device installation.

Use a disposable project and an already-supported non-Bluetooth input/output
route. Prefer headphones and keep the audio row/master unmuted. Record iPhone
model, iOS version, input/output accessory names, channel selection, and results.

1. Enable monitoring and speak for five seconds. Record for twenty seconds, stop,
   and keep speaking for five seconds. Live input must remain audible across both
   boundaries, including when transport stops. Monitoring stays visibly enabled.
2. Repeat three takes, including the capture-deck stop that keeps playback running.
   Play every saved take: its speech must be present throughout recording.
3. Quickly cancel a pending start. No take should be inserted; monitoring should
   continue and the next recording should work.
4. Monitor row A, then record into row B using the same input channels. The WAV
   belongs to B, while live monitoring stays routed through A.
5. Where the hardware exposes another selection, attempt recording with different
   channels. Expect a notice, no recording, and unchanged monitoring. Repeat normal
   recording in mono and stereo only where both are already supported.
6. Disable monitoring and record. Expect no live monitoring, but correct audio
   when playing the saved WAV.
7. Separately disconnect the active removable device during a take and during a
   pending start. Expect route invalidation/recovery, no stuck recording, and no
   silent restoration of the old monitor. Reconnect and explicitly enable
   monitoring before retrying.
8. Trigger an actual audio-session interruption during a take and separately
   during a pending start. After the interruption ends, verify the existing
   recovery behavior and a fresh recording; the old operation must not resume
   from a delayed completion. Simulator output is not sufficient evidence.

If a test fails, report the route, exact boundary, whether live output stopped,
and whether the WAV is correct. Preserve logs/route diagnostics for operation ID,
generation, endpoints, native callback readiness and capture report errors.
Writer faults and precise asynchronous races are injected in automated tests;
do not damage app storage to reproduce them manually.

## Verification status (2026-09-07)

- Foundation capture lifecycle tests passed.
- 184 shared coordinator and platform recording/route contract tests passed.
- 69 existing Android lifecycle/routing tests passed. The unrelated Android
  host-JNI placeholder failure remains documented in Android verification notes.
- Graph/WAV and existing macOS FIFO/WAV signal tests passed.
- Dart analysis: 452 diagnostics, matching the unchanged baseline after accounting
  for shifted line numbers; no new diagnostics.
- Final iOS unsigned device and macOS debug builds passed after the ownership
  review. Build-generated Podfile checksum churn was excluded from the change.
- Hardware acceptance was performed on the iPad below; no separate iPhone
  installation or acceptance was performed.
- iPad mini 5 (iPad11,1), iOS 26.5: in-place signed deployment succeeded.
  User testing exposed a flickering Record button with monitoring enabled.
  Logs showed native capture starting without a Dart capture result. The native
  reply was incorrectly boxed as an integer; the host regression reproduced it.
  The corrected signed build passed. Logs confirmed four monitored captures with
  successful recording-intent verification and stable routes, four readable
  48 kHz mono WAV files, and one successful monitoring-off capture.
  The user reported the listening test worked and subsequently reported that the
  requested edge-case checks all seemed fine. Individual accessory details and
  per-case measurements were not supplied; this is user-reported acceptance,
  not independently observed disconnection/interruption or audibility evidence.
  Temporary Dart diagnostics were removed after acceptance. The native boolean
  reply regression and lifecycle tests remain as automated coverage.
