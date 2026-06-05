# Integration Tests

This project includes an emulator-safe Flutter integration suite in:

- `integration_test/projects_flow_test.dart`

The suite uses a test-only app harness with fake auth and entitlement providers so it can run without real backend state.
It runs through `flutter drive`, which has been more reliable here for emulator/device end-to-end execution than `flutter test integration_test -d ...`.

Use the platform-aware wrapper to run the suite on Android or iOS.
The app uses `ffmpeg_kit_flutter_new_full` on both platforms.
The iOS JUCE podspec selects the simulator archive automatically through sdk-specific linker flags.

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
flutter drive \
  --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/projects_flow_test.dart \
  --device-id=<device-id> \
  --device-timeout=120 \
  --device-connection=attached \
  --no-dds
```
