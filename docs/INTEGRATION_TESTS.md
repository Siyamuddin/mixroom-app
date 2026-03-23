# Integration Tests

This project includes an emulator-safe Flutter integration suite in:

- `integration_test/projects_flow_test.dart`

The suite uses a test-only app harness with fake auth and entitlement providers so it can run without real backend state.
It runs through `flutter drive`, which has been more reliable here for emulator/device end-to-end execution than `flutter test integration_test -d ...`.

Before each run, use the platform-aware wrapper so the app is configured with the correct FFmpeg backend:

- iOS: `new_full`
- Android: `16kb`

The iOS JUCE podspec is kept in simulator-safe mode by commenting the `libJuceModules_debug3.a` line and uncommenting the `libJuceModules_sim.a` line.

The wrapper also prepends a local `tool/bin/xcrun` shim that clamps `xcdevice list` timeouts. This avoids Flutter hanging for long periods when macOS has a stale or unavailable paired iPhone in Apple device discovery.

## What It Covers

- Signed-in shell boots to the projects screen
- New project flow opens the audio editor
- Existing project flow opens the audio editor

## Run On Android Emulator

1. Start an Android emulator.
2. Confirm its device id:

```sh
flutter devices
```

3. Run the suite:

```sh
tool/run_integration_suite.sh android emulator-5554
```

## Run On iOS Simulator

1. Start an iOS simulator.
2. Confirm its device name or id:

```sh
flutter devices
```

3. Run the suite:

```sh
tool/run_integration_suite.sh ios "iPhone 16"
```

## Direct Command

```sh
dart run tool/switch_ffmpeg_backend.dart new_full   # iOS
dart run tool/switch_ffmpeg_backend.dart 16kb       # Android
flutter pub get
flutter drive \
  --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/projects_flow_test.dart \
  --device-id=<device-id> \
  --device-timeout=120 \
  --device-connection=attached \
  --no-dds
```
