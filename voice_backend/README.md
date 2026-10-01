# MixRoom local voice backend

One Docker container runs Python/FastAPI with a persistent SQLite database. It replaces the n8n server and the proposed Lovable Cloud relay. ElevenLabs handles command speech. OpenAI plans edits, and TypeSafe Jev optionally classifies requests. Audio processing, recording, instruments, and Basic Pitch stay in the native Mac application.

The existing validated planner is bundled as a small Node 22 worker inside the same container. Python owns authentication, the durable queue, state, pairing, and speech proxying. There is no n8n installation, webhook, Redis, or separate database service. See [planner details](planner/README.md).

## Start on this Mac

Docker Desktop must be running, with enough free storage to build the image. From this folder:

```sh
python3 scripts/setup_env.py
# Edit .env locally. Add OPENAI_API_KEY and ELEVENLABS_API_KEY.
# TYPESAFE_API_KEY is optional. Do not put these keys into the web app.
docker compose up --build -d
curl --fail http://127.0.0.1:8765/health
```

The setup script creates a random studio password and preserves an existing `.env`. The current workspace already has a private `.env` with the supplied ElevenLabs credential. OpenAI is still required for spoken request interpretation. Read `MIXROOM_PASSWORD` locally from `.env` when signing into the companion; never commit it.

```sh
docker compose logs --tail 50 backend
docker compose stop
```

The named `mixroom-data` volume survives stops and rebuilds. Do not use `docker compose down -v` unless intentionally deleting all pairing/session data. Native projects and recorded audio are stored separately by MixRoom.

For development while Docker is unavailable, `scripts/run_local.sh` runs the same Python service on loopback using `.venv`, the same `.env`, and `./data`. This is a development fallback, not evidence that the Docker image has been tested.

## Connect the companion and Mac

The browser app's source is currently in [`../voice_companion`](../voice_companion/), with the Lovable repository connection pending:

```sh
cd ../voice_companion
npm ci
npm run dev
```

Open `http://127.0.0.1:5173`, use studio address `http://127.0.0.1:8765/api/voice`, and enter the studio password. Select **Pair your Mac**. Start the native application with `../tool/run_hackathon.sh`, open a local project, and enter the displayed pairing code in its voice connection dialog.

For the published Lovable page or a phone, give the local backend an HTTPS address. One temporary demo option is a [Cloudflare Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/):

```sh
cloudflared tunnel --url http://127.0.0.1:8765
```

Use the printed HTTPS URL plus `/api/voice` as the studio address. Add the exact published Lovable origin to `MIXROOM_ALLOWED_ORIGINS`, then recreate the backend with `docker compose up -d --force-recreate`. A tunnel exposes the authenticated API, so the random studio password remains required. The Mac can continue using loopback. Quick Tunnel addresses are temporary; configure a named tunnel for repeated demonstrations. Tunnel setup and phone access have not yet been verified here.

## Reliability and configuration

- API base: `/api/voice`; local owner login/status/logout: `/api/auth`.
- Pairing codes expire after five minutes and can be used once. Browser and device sessions expire after twelve hours. Password rotation invalidates existing sessions on restart.
- SQLite stores hashed tokens, bounded state, commands, and outcomes; it does not store recordings or provider keys. Old command records expire after seven days.
- Command IDs are durable and duplicate submissions do not repeat an edit. Changed content under the same ID is rejected. Work is serialized per session, with project/revision checks before planning and application.
- Interrupted execution is reported as unknown, never automatically replayed. Recording and emergency stop do not depend on a working planning provider.
- New recording waits for microphone release and speech completion. A browser disconnect does not stop or discard an active native take.
- Backend binding is loopback only. CORS uses explicit browser origins. Keys remain server-side. Logs exclude raw provider bodies and credentials.
- One Uvicorn worker is intentional. Do not scale this local-owner deployment as a multi-tenant product without a separate design review.

Run tests with `.venv/bin/python -m pytest tests` from this folder. The planner also has Node contract tests. See the [implementation checklist](../docs/HACKATHON_IMPLEMENTATION.md) for what is implemented and what still needs a live Mac test.

## Verified on this Mac

The Docker image built successfully and the Compose service is running healthy on `127.0.0.1:8765`. Python tests: **31 passed plus eight subtests**. The real container passed login, one-use pairing, command deduplication, single native claim, result receipt, SQLite persistence through a restart, and live ElevenLabs token/TTS proxy checks with the latest supplied credential. These protocol fixtures do not perform native audio edits.

`./.venv/bin/python scripts/smoke_local.py` repeats the basic real HTTP check. `--speech` makes two small provider calls; `--restart` also restarts this Compose service, so run it before a musician connects.

OpenAI planning still needs `OPENAI_API_KEY`. Complete native recording/mixing/humming acceptance and the published Lovable connection remain pending.
