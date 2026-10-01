# MixRoom voice companion

React interface for the local MixRoom Python backend. The official Lovable project is [MixRoom](https://lovable.dev/projects/9f999e25-9d24-4f94-9560-34ca0b28be84). This tested source is preserved in the native repository until the Lovable GitHub connection creates `Siyamuddin/mixroom-voice`; it has not yet been integrated into or published from that project.

```sh
npm ci
npm run dev
```

Start [the backend](../voice_backend/README.md), open `http://127.0.0.1:5173`, and sign in with its studio address and password. `VITE_VOICE_RELAY_URL` is an optional public address default. No provider keys or studio password belong in frontend environment variables.

`npm test` covers microphone/speech lifecycle, command deduplication, recording readiness, session isolation, and auth URL handling. `npm run build` checks TypeScript and builds the production bundle. Browser outcomes come only from native-confirmed results. No simulated tracks or successful edits are shown when disconnected.

The browser uses ElevenLabs Scribe Realtime tokens minted by the backend and streamed TTS. Musical recording occurs on the Mac; microphone command input is paused during speech playback and performance capture. The studio supports mix commands, latest-change A/B, undo, timed recording, humming conversion, and notes through the shared [protocol](../docs/VOICE_PROTOCOL.md).
