# mixroom

Mixroom is the world's first AI-assisted music production app

## Developer Notes

The app uses `ffmpeg_kit_flutter_new_full` for Android, iOS, and macOS.
For Android Play releases, verify the final APK/AAB passes 16 KB native
library alignment checks before submission.

For iOS builds, [`juce_audio_engine/ios/juce_audio_engine.podspec`](juce_audio_engine/ios/juce_audio_engine.podspec) selects the correct JUCE archive automatically for simulator, debug device, and Profile/Release device builds.

## Legal

- Privacy Policy: https://mixroom.ai/privacy
- Terms of Service: `docs/TERMS_OF_SERVICE.md`
- End User License Agreement (EULA): `docs/EULA.md`
- Account Deletion: `docs/DELETE_ACCOUNT.md`
- Subprocessors: `docs/SUBPROCESSORS.md`
- Third-party notices: `docs/THIRD_PARTY_NOTICES.md`

## Third-party credits

- Instrument references and licensing notes: `docs/THIRD_PARTY_INSTRUMENT_CREDITS.md`
