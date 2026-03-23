# mixroom

Mixroom is the world's first AI-assisted music production app

## Developer Notes

Platform-specific local setup is required before running the app:

- Android uses the FFmpeg `16kb` variant:
  `dart run tool/switch_ffmpeg_backend.dart 16kb`
- iOS uses the FFmpeg `new_full` variant:
  `dart run tool/switch_ffmpeg_backend.dart new_full`
- After switching FFmpeg variants, run `flutter pub get`.

For iOS builds, also check [`juce_audio_engine/ios/juce_audio_engine.podspec`](juce_audio_engine/ios/juce_audio_engine.podspec) and make sure `s.ios.vendored_libraries` matches the target you are about to run:

- Debug on a real device: uncomment `ios-arm64/libJuceModules_debug3.a`
- Release on a real device: uncomment `ios-arm64/libJuceModules.a`
- Simulator: uncomment `ios-arm64_x86_64-simulator/libJuceModules_sim.a`

Keep the other two entries commented out.

## Legal

- Privacy Policy: https://mixroom.ai/privacy
- Terms of Service: `docs/TERMS_OF_SERVICE.md`
- End User License Agreement (EULA): `docs/EULA.md`
- Account Deletion: `docs/DELETE_ACCOUNT.md`
- Subprocessors: `docs/SUBPROCESSORS.md`
- Third-party notices: `docs/THIRD_PARTY_NOTICES.md`

## Third-party credits

- Instrument references and licensing notes: `docs/THIRD_PARTY_INSTRUMENT_CREDITS.md`

## iOS App Store build requirement

Starting April 28, 2026, App Store Connect requires builds made with the iOS 26 SDK (Xcode 26+).

Run this before release/TestFlight uploads:

```bash
./tools/ios/check_xcode_26_sdk.sh
```
