# DIGITAL AF implementation and acceptance

## Current architecture

The user's final backend choice is local Python in Docker. The earlier n8n and Lovable Cloud backend designs are superseded. Lovable remains the browser product for hackathon eligibility; its generated project exists, but GitHub linking and publication are still pending.

The Docker image is built. After initial container checks passed, Docker's outbound networking stopped responding for both providers and the host route. The same Python service is temporarily running directly on the Mac for manual testing. Only MixRoom's container was stopped, and its database volume was preserved; unrelated containers and global Docker settings were not reset. Follow the active addresses in [the manual guide](MANUAL_TESTING.md).

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
- Hackathon isolation test passed. The final focused voice/session/comparison/transport and isolation run passed 19 tests, with no skipped tests.
- Native local HTTP policy, actual loopback pairing/poll transport, redirect rejection and durable journal restart passed standalone Dart checks. Analyzer reported no errors or warnings.
- Browser session, speech lifecycle and local-auth tests: 36 passed. Production build and TypeScript passed. The sign-in page was visually checked in the browser. The isolated ARM64 Mac app was built, its deep code signature verified, its new home screen confirmed in the packaged code, and its process launched. Desktop UI inspection timed out, so native interaction and microphone acceptance remain unverified.
- Local planner: nine Python-to-Node lifecycle/compatibility tests and ten V3/voice contract tests passed. All nine final real OpenAI planning cases passed through the host HTTP API on port 8766: gain targets, comparison before/after, ten-second capture, three combined humming/conversion phrases, clarification of unrelated capture-plus-edit intent, and an explicit note. These fixture commands were never executed in the native app. Planning took 2.2–7.4 seconds per case in this run.
- ElevenLabs direct live smoke passed: Sarah streaming TTS, single-use Scribe token, and realtime transcription of a synthetic spoken fixture. These are provider checks, not a live musician demonstration.
- Final host HTTP ElevenLabs checks passed: single-use token issuance in 404 ms and TTS audio response in 472 ms (30,974 bytes). Audio was not played or stored during this check.
- Actual bundled Basic Pitch ONNX inference and MixRoom's Dart note decoder recovered all eight expected pitches from an eight-second generated melody: A4 C5 E5 C5 A4 G4 E4 A4. Note starts were within 18 ms of the fixture. Model processing took 253 ms and decoding 29 ms in one run. This used an isolated harness; native plugin invocation, microphone humming, and editor MIDI insertion remain unchecked.
- Python backend: 37 tests and eight subtests passed, including real SQLite transactions, Python-to-Node worker integration, the public service page, pairing throttle boundaries, and the scoped Docker connection helper. Real local HTTP checks passed for login, origin rejection, pairing, deduplication, single claim, result receipt, and ElevenLabs token/audio proxying.
- The later URL check found a stale development server returning 504 for its JavaScript modules, despite an HTTP 200 index. The demo now serves the built browser bundle on port 5173. Fresh browser rendering, login, and real pairing creation/revocation passed. The backend root on port 8766 now shows a status page instead of a 404. Authenticated pairing is limited to five per minute, replacing a five-per-hour limit that blocked recovery after earlier tests; public login and pairing-code protections remain unchanged.
- The local Docker image was updated offline with these backend fixes, and its application file matches the tested source. Docker startup still stalls on this Mac; the updated image has not passed a fresh runtime check. The working demo continues to use the host backend.
- The browser signed into the real local Python service and generated a pairing code. No native track edit was performed during these protocol checks.
- The Docker image built successfully and uses UID 10001 with loopback port 8765. Container health, authentication, single-use pairing, duplicate commands, single claim, result receipt, persistent results after container restart, and live ElevenLabs token/audio proxying passed with the latest supplied credential before Docker's outbound networking failed. Docker Desktop was initially restored by re-enabling its specific disabled application service; no global restart was performed when the later network failure occurred.

## Still required before submission

- Add a TypeSafe key only if demonstrating Jev; otherwise describe the tested OpenAI route accurately.
- Restore Docker Desktop's provider connectivity before claiming the final combined humming workflow is verified in Docker. The host fallback uses the same backend/planner source.
- Maintain enough free space for recordings and subsequent builds. The isolated debug app now builds successfully with the documented reduced-metadata Xcode override; failed-build/test caches and regenerable package downloads were reclaimed during the build.
- Run the actual editor comparison integration test. The focused native voice/transport/comparison/isolation tests have passed.
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
