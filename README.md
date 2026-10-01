# MixRoom — DIGITAL AF voice studio

Independent macOS fork of the original MixRoom `ai-v4` checkpoint `df4f86e9`.
The original application and repository are unchanged. Existing attribution and
license notices below and in the source remain in force.

- Native application: [Siyamuddin/mixroom-app](https://github.com/Siyamuddin/mixroom-app) (private).
- Hosted controls: [MixRoom on Lovable](https://mix-voice-studio.lovable.app). Published-browser sign-in, pairing-code creation, and session revocation are verified.
- Companion repository: [Siyamuddin/mixroom-voice](https://github.com/Siyamuddin/mixroom-voice) (private, connected to Lovable).
- [Build and run the isolated macOS flavor](tool/HACKATHON_MACOS.md).
- [Test the app step by step on this Mac](docs/MANUAL_TESTING.md).
- [Implementation, configuration, acceptance checks, and demo](docs/HACKATHON_IMPLEMENTATION.md).

The hosted browser controls connect through a temporary HTTPS tunnel to the
**Python/FastAPI backend on this Mac**, with SQLite and direct OpenAI planning.
ElevenLabs provides command transcription and spoken responses. The native Mac
app records and plays audio, applies effects, and runs Basic Pitch locally.
[Start the backend](voice_backend/README.md). Its Docker image is available, but
the active runtime uses host Python because Docker networking is unavailable.
Optional Jev classification is not configured in the verified setup.

The [companion source](voice_companion/) is retained as the local standalone
version. The Lovable-connected repository hosts the integrated browser version.
For the current native connection, use `http://127.0.0.1:8766/api/voice`.
Retrieve the studio password privately from `MIXROOM_PASSWORD` in the ignored
`voice_backend/.env`; paste only its value into the sign-in form.

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
