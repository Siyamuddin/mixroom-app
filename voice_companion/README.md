# MixRoom voice companion

React interface for the local MixRoom Python backend. The official Lovable project is [MixRoom](https://lovable.dev/projects/9f999e25-9d24-4f94-9560-34ca0b28be84), connected to the private [Siyamuddin/mixroom-voice](https://github.com/Siyamuddin/mixroom-voice) repository. The integrated controls are published at [mix-voice-studio.lovable.app](https://mix-voice-studio.lovable.app). Its actual browser sign-in, pairing-code creation, disabled controls while waiting for the Mac, and session revocation passed. This folder remains the tested standalone local companion.

The hosted controls reach the Mac's Python backend through an HTTPS tunnel. The native Mac app connects to that same backend at `http://127.0.0.1:8766/api/voice` and owns all music recording, playback, edits, and humming conversion. The hosted page alone does not run the native audio engine. See [the current connection steps](../docs/MANUAL_TESTING.md).

```sh
npm ci
npm run build
npm run preview -- --port 5173 --strictPort
```

For local testing, start [the backend](../voice_backend/README.md), open `http://127.0.0.1:5173`, and use studio address `http://127.0.0.1:8766/api/voice`. Open the ignored `voice_backend/.env` privately in an editor and copy only the `MIXROOM_PASSWORD` value into the password field; do not put it in a screenshot, shared message, or repository. For the hosted page or a phone, use the HTTPS studio address from the manual guide. `VITE_VOICE_RELAY_URL` is an optional public address default. No provider keys or studio password belong in frontend environment variables.

The current demo serves the built bundle, avoiding development-server reloads during a presentation. Rebuild after source or public environment changes. For development, stop the preview first and use `npm run dev`; do not run both on port 5173.

`npm test` covers microphone/speech lifecycle, command deduplication, recording readiness, session isolation, and auth URL handling. `npm run build` checks TypeScript and builds the production bundle. Browser outcomes come only from native-confirmed results. No simulated tracks or successful edits are shown when disconnected.

The browser uses ElevenLabs Scribe Realtime tokens minted by the backend and streamed TTS. Musical recording occurs on the Mac; microphone command input is paused during speech playback and performance capture. The studio implements mix commands, latest-change A/B, undo, timed recording, humming conversion, and notes through the shared [protocol](../docs/VOICE_PROTOCOL.md). Live microphone acceptance and the full five-feature native demonstration remain unverified.
