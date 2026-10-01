# MixRoom — DIGITAL AF voice studio

Independent macOS fork of the original MixRoom `ai-v4` checkpoint `df4f86e9`.
The original application and repository are unchanged. Existing attribution and
license notices below and in the source remain in force.

- Native application: [Siyamuddin/mixroom-app](https://github.com/Siyamuddin/mixroom-app) (private).
- Companion: Lovable project **MixRoom**, intended private repository `Siyamuddin/mixroom-voice`.
- [Build and run the isolated macOS flavor](tool/HACKATHON_MACOS.md).
- [Implementation, configuration, acceptance checks, and demo](docs/HACKATHON_IMPLEMENTATION.md).

The backend is a **local Python/FastAPI service in Docker**, with SQLite and
direct OpenAI / optional Jev planning. [Start the backend](voice_backend/README.md).
It does not require n8n or Lovable Cloud. ElevenLabs provides command transcription and spoken responses.
Audio recording, playback, effects, and Basic Pitch transcription run locally.

The [companion source](voice_companion/) is included here while Lovable's GitHub
connection is pending. Its destination remains `Siyamuddin/mixroom-voice`.

Implementation includes voice mixing, guarded before/after and undo, timed takes,
humming to editable MIDI, and persistent session notes. Local tests have passed;
live end-to-end acceptance and release packaging are still pending. Do not treat
an implemented feature as a verified release until the checklist is completed.

---

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
