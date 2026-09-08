# macOS monitoring and recording verification (PRO-72)

This first implementation preserves an already-enabled, verified non-Bluetooth
monitoring session while recording the same input channels. The recording row
may differ from the monitored row; monitoring retains its target. Different
input channels are rejected with a notice while retaining monitoring. Bluetooth
and independent-clock conversion remain follow-up work, not validated support.

## Automated checks

From the repository root:

```sh
python3 tool/test_macos_monitor_capture.py
flutter test test/live_input_monitoring_v2_contract_test.dart test/macos_bluetooth_v2_recording_contract_test.dart test/realtime_wav_capture_contract_test.dart test/ios_bluetooth_v2_recording_contract_test.dart test/android_bluetooth_v2_recording_contract_test.dart juce_audio_engine/test/audio_route_coordinator_v2_test.dart
flutter build macos --debug
```

The native test compiles production monitoring-buffer and WAV-writer code. It
checks actual output samples and the finalized WAV for mono/stereo at 64, 256,
and 1024 frames, including repeated takes, discard, writer-start failure, and
monitoring disabled. It opens no devices. Contract tests check platform wiring;
coordinator tests execute the Dart state machine with a fake native adapter.
These do not replace a hardware listening test of AUHAL and the output graph.

## Mac listening test

Use an input/output configuration where monitoring is already available. Use
headphones, an unmuted audio row and master, and neutral effects. Record the
actual device names, rates and buffer size used.

1. Enable input monitoring. Speak continuously for five seconds.
2. Record for twenty seconds while continuing to speak. There must be no change
   in monitoring when recording starts.
3. Stop using the normal Record button. Continue speaking for five seconds;
   monitoring must remain audible even with transport stopped.
4. Repeat using the capture-deck button (keep playing), then repeat quickly
   cancelling a pending start. Monitoring must remain active.
5. Record another row configured for the same input channels. Confirm the
   monitoring row/processing does not move.
6. Select different channels and attempt to record. Confirm the explanatory
   notice, no take started, and monitoring still audible.
7. Disable monitoring and record. Confirm the WAV contains input without live
   monitoring. Play back all successful takes and verify their contents.
8. In a disposable project, disconnect the active input/output during a take.
   Confirm one route failure/recovery response, no stuck recording state, and
   no publication of an invalid take. Reconnect and explicitly re-enable
   monitoring before repeating the normal test.

Bluetooth output + separate mic, Bluetooth headset duplex, and differing input
and output channels need the subsequent implementation before acceptance.
