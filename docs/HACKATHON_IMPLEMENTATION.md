# DIGITAL AF implementation and acceptance

## Current architecture

The user's final backend choice is local Python in Docker. The earlier n8n and Lovable Cloud backend designs are superseded. Lovable remains the browser product for hackathon eligibility; its generated project exists, but GitHub linking and publication are still pending.

```text
Lovable / React microphone
  → ElevenLabs Scribe Realtime (temporary server-issued token)
  → Python relay / SQLite durable command
  → Mac fresh project context
  → Python planner adapter → bundled V3 worker → OpenAI / optional Jev
  → native validation, apply, readback, undo journal
  → Python verified result → browser → ElevenLabs spoken response
```

The backend is [`voice_backend`](../voice_backend/README.md). The companion source is preserved at [`voice_companion`](../voice_companion/README.md) while the intended private Lovable repository is pending. The native repository is private `Siyamuddin/mixroom-app`, based on the original `ai-v4` checkpoint `df4f86e9`. The original working directory and Git configuration were left untouched.

## Implemented features

1. **Spoken mixing:** fresh native context; stable track targets; existing V3 preparation, validation, execution and readback; distinct clarification/failure outcomes. Existing volume, pan, mute/solo, effects and transport actions are reused.
2. **Before/after and undo:** compare the latest eligible verified mix transaction, with action identity and exact state guards. Edits/autosave are blocked during temporary before-state playback. Commit the chosen side; restore after cancellation or disconnection; invalidate after intervening work. Structural edits and captures are excluded.
3. **Timed recording:** validate input and selected track, stop assistant speech and command recognition, await readiness, count down two seconds, record locally, stop and save. Default ten seconds, maximum sixty. Bars use actual tempo and time signature. The browser emergency stop bypasses queued edits.
4. **Hum to instrument:** retain the audio take, run local Basic Pitch, create a separate MIDI result with the installed warm-keys instrument by default, and expose existing playback/instrument/transpose/undo actions. Empty transcriptions fail explicitly.
5. **Spoken notes:** explicit note requests store text with project identity, playhead and optional track. Notes persist locally, can be read aloud/completed, and never execute as audio edits.

The Hackathon macOS configuration has a separate bundle ID and data directory and disables the original product's account startup, subscriptions, billing, cloud synchronization, telemetry and automatic updates. Provider keys are confined to the Python backend's ignored `.env`.

## Verification completed

- Existing focused AI configuration, transaction, execution, mixing, audio-to-MIDI and undo tests: 84 passed.
- Hackathon isolation test passed. New voice/controller/comparison tests passed before the local-backend transport changes.
- Native local HTTP policy, actual loopback pairing/poll transport, redirect rejection and durable journal restart passed standalone Dart checks. Analyzer reported no errors or warnings.
- Browser session, speech lifecycle and local-auth tests: 36 passed. Production build and TypeScript passed. The sign-in page was visually checked in the browser.
- Local planner: nine Python-to-Node lifecycle/compatibility tests and ten V3/voice contract tests passed.
- ElevenLabs direct live smoke passed: Sarah streaming TTS, single-use Scribe token, and realtime transcription of a synthetic spoken fixture. These are provider checks, not a live musician demonstration.
- Python backend: 31 tests and eight subtests passed, including real SQLite transactions and Python-to-Node worker integration. Real local HTTP checks passed for login, origin rejection, pairing, deduplication, single claim, result receipt, and ElevenLabs token/audio proxying.
- The browser signed into the real local Python service and generated a pairing code. No native track edit was performed during these protocol checks.
- The Docker image built successfully and runs as UID 10001 on loopback port 8765. Container health, authentication, single-use pairing, duplicate commands, single claim, result receipt, persistent results after container restart, and live ElevenLabs token/audio proxying passed with the latest supplied credential. Docker Desktop was restored by re-enabling its specific disabled application service.

## Still required before submission

- Add a valid OpenAI key. Add a TypeSafe key only if demonstrating Jev; otherwise describe the OpenAI route accurately.
- Free sufficient disk space and build the isolated Mac app. The first build failed during CocoaPods downloads; the second completed CocoaPods and reached native/JUCE compilation, then the disk guard stopped it at 464 MiB free. No compiler error was identified before interruption. Only this new copy’s failed build outputs were removed to free space for the backend.
- Run the added Flutter transport tests and actual editor comparison integration test.
- Verify all five features against the real Mac app, including a known melody fixture and live microphone humming, exact A/B values, manual-edit invalidation, disconnected recording, unknown-result recovery, stale-project rejection and notes after reopening.
- Finish Lovable GitHub authorization, create the private `Siyamuddin/mixroom-voice` through its integration, integrate the tested companion source, configure the HTTPS tunnel/allowed origin and publish the Lovable site.
- Exercise the published page from both laptop and phone. Measure recognition, planning, native execution and response latency separately.

Do not present the project as release-ready until these checks pass. The UI must never show a fake completed edit because providers, the tunnel, or the native app are unavailable.

## Two-minute demo script

Prepare a local project with a named vocal/audio track, a backing track, headphones, working input, and the warm-keys instrument. Pair the published Lovable page before recording the demo.

| Time | Action |
| --- | --- |
| 0:00–0:15 | Explain the solo-musician problem: hands are occupied playing while recording/editing. Show the live Lovable page and connected Mac. |
| 0:15–0:45 | Say “Hum for ten seconds and turn it into piano.” Wait for countdown, hum a short melody, and play the MIDI result. |
| 0:45–1:15 | Say “Lower the backing track by two decibels.” Show the native-confirmed value; ask for before/after and keep the preferred version. |
| 1:15–1:35 | Say “Remember: try a quieter guitar in the second verse.” Show the time-stamped saved note. |
| 1:35–2:00 | Explain ElevenLabs command transcription and spoken responses, local music processing, and the existing native DAW foundation. |

Submission fields: **MixRoom**; pitch “A voice-controlled studio for musicians whose hands are busy playing”; published Lovable link; audio-on video under two minutes; accurate ElevenLabs description; team members. State that the native DAW is the reused foundation. Do not claim Jev, publication, or end-to-end operation unless verified.
