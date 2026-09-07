# Android monitoring and recording verification (PRO-72)

Scope: Android V2, with monitoring already working on a supported non-Bluetooth
route. A take shares the monitored input channels, even when recording into a
different row. Bluetooth monitoring and new device configurations are excluded.

## Automated checks

Run from the repository root (set JAVA_HOME to your installed JDK if necessary):

```sh
android/gradlew -p android :juce_audio_engine:testDebugUnitTest --tests '*Android*Test'
flutter test test/live_input_monitoring_v2_contract_test.dart test/android_bluetooth_v2_recording_contract_test.dart test/realtime_wav_capture_contract_test.dart test/macos_bluetooth_v2_recording_contract_test.dart test/ios_bluetooth_v2_recording_contract_test.dart juce_audio_engine/test/audio_route_coordinator_v2_test.dart
flutter build apk --debug --target-platform android-arm64
```

The full Kotlin suite also includes an existing `JuceAudioEnginePluginTest`
placeholder that loads the Android native library on the host JVM. It fails
with `UnsatisfiedLinkError` on this Mac both before and after this change.
The command above runs the behavioral Android lifecycle and routing tests.

The capture tests use an injectable native bridge to exercise repeated takes,
mono/stereo selection, mismatches, duplicate starts, pending cancellation,
writer-start/finalization failures and stale start/stop completions. They check
capture-only cleanup and preservation of fake monitor ownership/stream epoch.
Source-contract tests separately check production JNI wiring and callback
fan-out; these assertions do not establish audible output.

The host signal test uses a real JUCE graph and the production WAV writer,
without opening audio devices. On macOS, supply the Debug JUCE framework archive
from a macOS app build:

```sh
python3 tool/test_android_monitor_capture.py --juce-library build/macos/Build/Products/Debug/juce_audio_engine/juce_audio_engine.framework/Versions/A/juce_audio_engine
python3 tool/test_macos_monitor_capture.py
```

It compares output and saved samples for mono/stereo at 64, 256 and 1024 frames,
including repeated takes, cancellation, failed writer creation, and monitoring
off. This models Android's callback fan-out; it does not execute Android JNI,
the device driver, or the full app row/effect graph. The APK build checks native
integration, and the following device test checks actual audibility.

## User-performed Android acceptance

Use a disposable project, headphones, an unmuted audio row/master and neutral
effects. First confirm monitoring works with the selected non-Bluetooth route.
Record device model, Android version, input/output names and selected channels.
Do not switch devices to make an unsupported configuration appear supported.

1. Enable monitoring and speak for five seconds. Record for twenty seconds,
   then stop and continue speaking for five seconds. Live input must remain
   audible across both boundaries, including with transport stopped. The
   monitoring toggle stays enabled and is locked while recording/transitions.
2. Repeat three times, including the capture-deck stop that keeps playback
   running. Play the saved takes: each must contain the spoken input throughout.
3. Quickly cancel a pending record start. No take should be inserted; monitoring
   must continue and the next normal take must work.
4. Record into another audio row with the same input channel selection. The take
   belongs to that row; monitoring remains routed through the original row.
5. If the current hardware exposes another channel selection, select it and try
   recording. Expect a notice and no take; the original monitor remains audible.
   Repeat mono/stereo only where both were already supported by that device.
6. Disable monitoring and record. Expect no live monitor output, but correct
   spoken audio when playing the saved take.
7. Separately disconnect the active removable device during a take and during a
   pending start. Expect route invalidation/recovery, no stuck recording state,
   and no old monitor session silently restored. Reconnect and explicitly enable
   monitoring again before repeating step 1.

If a step fails, note the exact boundary, route and whether the WAV is correct.
Capture app/`JuceAudioEngine` logs and route diagnostics where available; use
endpoint fingerprints, stream epoch, callback readiness and capture report
errors to explain the failure. Diagnostics support the listening result and
cannot replace it. Writer failures and precise asynchronous races are covered
by automated injection, not by forcing storage/device faults in normal use.

## Implementation verification recorded on 2026-09-07

- 69 Android Kotlin lifecycle/routing tests passed (10 new capture tests).
- 154 shared coordinator and Android/macOS/iOS recording contract tests passed.
- Android-style graph/WAV and existing macOS FIFO/WAV signal tests passed.
- ARM64 Android debug APK built successfully with the installed SDK/NDK/CMake.
- Dart analysis matched the unchanged `6be5610a` baseline: 452 existing
  diagnostics, no new diagnostics after normalizing shifted line numbers.
- Full Kotlin suite's host JNI-loading placeholder failure was reproduced on
  the unchanged baseline; it is not included in the 69 passing tests above.
- User-performed Android acceptance: the user tested the PRO-72 debug build on
  the connected Samsung SM-S918N and reported that everything seemed fine,
  including after receiving the remaining cancellation, alternate-row,
  monitoring-off and device-disconnection checklist. Exact audio accessory/route
  details and individual case results were not recorded. This acceptance applies
  to the tested configuration; it does not establish Bluetooth monitoring support.
