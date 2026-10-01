# MixRoom local voice backend

Python/FastAPI and SQLite run on the musician's Mac. The current host runtime listens on `127.0.0.1:8766`; a Docker image is also available. The published [Lovable controls](https://mix-voice-studio.lovable.app), from the private [mixroom-voice repository](https://github.com/Siyamuddin/mixroom-voice), connect through an HTTPS tunnel. Published-browser sign-in, pairing-code creation, and session revocation are verified. ElevenLabs handles command speech and OpenAI plans edits. Optional TypeSafe Jev classification is not configured in this verified setup. Audio processing, recording, instruments, and Basic Pitch stay in the native Mac application.

The validated planner is a bundled Node 22 worker alongside Python, included in the same Docker image when using Docker. Python owns authentication, the durable queue, state, pairing, and speech proxying. See [planner details](planner/README.md).

## Start on this Mac

For the currently running test setup, follow [the manual guide](../docs/MANUAL_TESTING.md). Docker's outbound networking failed after the image and initial protocol checks passed. The same Python service is temporarily running on the Mac so provider calls can work; the Docker image and database volume remain available. The guide gives the active address and restart command.

Docker Desktop must be running, with enough free storage to build the image. From this folder:

```sh
python3 scripts/setup_env.py
# Edit .env locally. Add OPENAI_API_KEY and ELEVENLABS_API_KEY.
# TYPESAFE_API_KEY is optional. Do not put these keys into the web app.
docker compose up --build -d
curl --fail http://127.0.0.1:8765/health
```

The setup script creates a random studio password and preserves an existing `.env`. The current workspace already has a private `.env` with the supplied ElevenLabs credential. The supplied OpenAI credential is configured for spoken request interpretation. Read `MIXROOM_PASSWORD` locally from `.env` when signing into the companion; never commit it.

```sh
docker compose logs --tail 50 backend
docker compose stop
```

The named `mixroom-data` volume survives stops and rebuilds. Do not use `docker compose down -v` unless intentionally deleting all pairing/session data. Native projects and recorded audio are stored separately by MixRoom.

For development while Docker is unavailable, `scripts/run_local.sh` runs the same Python service on loopback using `.venv`, the same `.env`, and `./data`. This is a development fallback, not evidence that the Docker image has been tested.

## Connect the companion and Mac

Open the published [Lovable controls](https://mix-voice-studio.lovable.app), or run the standalone local companion from [`../voice_companion`](../voice_companion/):

```sh
cd ../voice_companion
npm ci
npm run dev
```

For the local companion, open `http://127.0.0.1:5173` and use studio address `http://127.0.0.1:8766/api/voice` for the current host runtime (`8765` for Docker). For the hosted page, use the HTTPS address below. Retrieve the studio password privately by opening the ignored `.env` locally and copying only the `MIXROOM_PASSWORD` value into the sign-in form. Select **Pair your Mac**, then open the native app and a local project as described in [the manual guide](../docs/MANUAL_TESTING.md). Enter that pairing code with native relay URL `http://127.0.0.1:8766/api/voice`. Both browser and Mac reach the same backend; the native URL can remain local even when the browser uses HTTPS.

The current [Cloudflare Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) exposes only this backend. Its temporary studio address is `https://accidents-enzyme-archived-members.trycloudflare.com/api/voice`. Keep the Mac, Python backend, and tunnel running. If the tunnel has stopped, the locally downloaded official binary can start a new one:

```sh
/tmp/mixroom-cloudflared/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8766
```

A restart generates a different hostname: use the new printed HTTPS URL plus `/api/voice` in the browser and update the hosted default when needed. The binary and logs are under `/tmp/mixroom-cloudflared` and may disappear after a Mac restart. Do not start a second tunnel while the existing one is working. The exact published origin `https://mix-voice-studio.lovable.app` and the project's exact Lovable preview origin are already allowed in the private backend configuration. Public HTTPS health checks and authenticated login/status/logout with both origins passed; unknown origins were rejected. This verifies the HTTPS API path, not the published browser or phone microphone. A Quick Tunnel is temporary and has no uptime guarantee. The studio password remains required.

## Reliability and configuration

- API base: `/api/voice`; local owner login/status/logout: `/api/auth`.
- Pairing codes expire after five minutes and can be used once. Browser and device sessions expire after twelve hours. Password rotation invalidates existing sessions on restart.
- An authenticated owner can create five pairing codes per minute. Reaching that limit does not prevent an already connected session from operating.
- SQLite stores hashed tokens, bounded state, commands, and outcomes; it does not store recordings or provider keys. Old command records expire after seven days.
- Command IDs are durable and duplicate submissions do not repeat an edit. Changed content under the same ID is rejected. Work is serialized per session, with project/revision checks before planning and application.
- Interrupted execution is reported as unknown, never automatically replayed. Recording and emergency stop do not depend on a working planning provider.
- New recording waits for microphone release and speech completion. A browser disconnect does not stop or discard an active native take.
- Backend binding is loopback only. CORS uses explicit browser origins. Keys remain server-side. Logs exclude raw provider bodies and credentials.
- One Uvicorn worker is intentional. Do not scale this local-owner deployment as a multi-tenant product without a separate design review.

Run tests with `.venv/bin/python -m pytest tests` from this folder. The planner also has Node contract tests. See the [implementation checklist](../docs/HACKATHON_IMPLEMENTATION.md) for what is implemented and what still needs a live Mac test.

## Verified on this Mac

The Docker image built successfully. Python tests: **37 passed plus eight subtests**. Before Docker's outbound networking stopped responding, the real container passed login, one-use pairing, command deduplication, single native claim, result receipt, SQLite persistence through a restart, and live ElevenLabs token/TTS proxy checks with the latest supplied credential. These protocol fixtures do not perform native audio edits. MixRoom's container is now stopped while the host runtime is used; other containers were left running. The current host's base URL displays a service status page, and real browser sign-in and pairing have been verified.

`./.venv/bin/python scripts/smoke_local.py` repeats the basic real HTTP check. `--speech` makes two small provider calls; `--restart` also restarts this Compose service, so run it before a musician connects.

Live OpenAI planning has been tested with the supplied server-side credential. The published Lovable browser passed sign-in, pairing-code creation, waiting-for-Mac controls, and session revocation. Complete native recording/mixing/humming acceptance and phone microphone access remain pending. See [step-by-step manual testing](../docs/MANUAL_TESTING.md).

The current host service is on `127.0.0.1:8766` because Docker Desktop still holds port 8765. All nine final real OpenAI planning cases and ElevenLabs token/TTS calls passed through that host HTTP service. To repeat this explicit live-provider check (uses credits), run `.venv/bin/python scripts/smoke_planner.py --live --base-url http://127.0.0.1:8766 --speech`. It uses fixture context and never executes native edits or records microphone audio.

If ordinary Docker CLI commands hang on this Mac, use `python3 scripts/docker_local.py compose ps` (or replace `ps` with another Compose command). It probes the default connection, then Docker Desktop’s local raw socket, without changing the global Docker context.
