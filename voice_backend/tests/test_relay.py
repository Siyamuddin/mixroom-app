"""Real SQLite/HTTP behavior with offline provider doubles, never live AI calls."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import json
import time
import uuid

from fastapi.testclient import TestClient
import httpx
import pytest

from mixroom_backend.app import create_app
from mixroom_backend.config import Settings
from mixroom_backend.protocol import RelayError, digest, iso, sanitize_context
from mixroom_backend.store import Store

PASSWORD = "local-owner-test-password"
ORIGIN = "http://localhost:5173"


@pytest.fixture
def relay(tmp_path):
    now = [time.time()]
    settings = Settings(password=PASSWORD, data_dir=str(tmp_path), elevenlabs_api_key="test-private-key", elevenlabs_voice_id="test-voice", openai_api_key="test-openai-key")
    provider_calls, plans, holder = [], [], {}

    async def provider(request):
        provider_calls.append(request)
        if holder.get("during_speech"): holder["during_speech"]()
        if "single-use-token" in str(request.url): return httpx.Response(200, json={"token": "one-use-token"})
        return httpx.Response(200, content=b"test-mp3-frames", headers={"content-type": "audio/mpeg"})

    async def planner(payload, config):
        plans.append((payload, config))
        if holder.get("during_plan"): holder["during_plan"]()
        return {"httpStatus": 200, "response": {"kind": "session_action", "action": {"type": "notes.add", "arguments": {"text": "Chorus note"}}}}

    app = create_app(settings, provider_transport=httpx.MockTransport(provider), planner=planner, mix_resolver=planner, clock=lambda: now[0])
    with TestClient(app) as client:
        login = client.post("/api/auth/login", json={"password": PASSWORD})
        assert login.status_code == 200
        owner_token = login.json()["access_token"]
        owner = {"Authorization": f"Bearer {owner_token}", "Origin": ORIGIN}
        pairing = client.post("/api/voice/pairing", json={}, headers=owner).json()
        claim = client.post("/api/voice/pairing/claim", json={"pairingCode": pairing["pairingCode"], "deviceName": "Test Mac"}).json()
        native_token = claim["deviceToken"]
        native = {"Authorization": f"Bearer {native_token}"}
        sid = claim["sessionId"]
        base = f"/api/voice/sessions/{sid}"
        state = {"projectSessionId": "project-one", "projectRevision": 1, "state": {"projectName": "Demo", "projectReady": True, "recordingPhase": "idle"}}
        assert client.put(base + "/state", json=state, headers=native).status_code == 200

        def command(**changes):
            return {"version": 1, "commandId": str(uuid.uuid4()), "sessionId": sid, "projectSessionId": "project-one", "expectedProjectRevision": 1,
                    "kind": "utterance", "args": {"text": "Lower the vocal"}, "expiresAt": iso(now[0] + 120), **changes}

        holder.update(client=client, app=app, store=app.state.store, settings=settings, now=now, owner=owner, native=native,
                      owner_token=owner_token, native_token=native_token, sid=sid, base=base, command=command, state=state,
                      native_actor={"device_hash": digest(native_token)}, browser_actor={"owner": True}, pairing=pairing,
                      provider_calls=provider_calls, plans=plans)
        yield holder


def test_owner_login_hashes_tokens_and_password_and_logout_revokes(relay):
    f = relay
    assert f["client"].get("/api/auth/status", headers=f["owner"]).json()["user"] == {"id": "owner"}
    assert f["client"].get("/api/auth/status", headers=f["native"]).status_code == 403
    rows = str([tuple(row) for row in f["store"].db.execute("SELECT * FROM owner_tokens")])
    verifier = str([tuple(row) for row in f["store"].db.execute("SELECT * FROM auth_config")])
    assert f["owner_token"] not in rows and PASSWORD not in verifier
    assert f["client"].post("/api/auth/logout", headers=f["owner"]).status_code == 200
    assert f["client"].get("/api/auth/status", headers=f["owner"]).status_code == 401


def test_login_rate_limits_are_durable_and_expire(relay):
    f = relay
    for _ in range(4): assert f["client"].post("/api/auth/login", json={"password": "wrong-password"}).status_code == 401
    assert f["client"].post("/api/auth/login", json={"password": PASSWORD}).status_code == 429
    f["now"][0] += 61
    assert f["client"].post("/api/auth/login", json={"password": PASSWORD}).status_code == 200


def test_exact_cors_and_server_date_on_errors(relay):
    f = relay
    assert f["client"].get("/health").json()["ok"] is True
    assert f["client"].get("/health", headers={"Origin": "https://untrusted.invalid"}).status_code == 403
    response = f["client"].get(f["base"] + "/commands/" + str(uuid.uuid4()), headers=f["owner"])
    assert response.status_code == 404 and response.json()["error"]["code"] == "command_not_found"
    assert response.headers["Access-Control-Expose-Headers"] == "Date" and response.headers["Date"]
    allowed = f["client"].options("/api/voice/pairing", headers={"Origin": ORIGIN, "Access-Control-Request-Private-Network": "true"})
    assert allowed.status_code == 204 and allowed.headers["Access-Control-Allow-Private-Network"] == "true"


def test_pairing_single_use_expiry_and_wrong_device(relay):
    f = relay
    assert f["client"].post("/api/voice/pairing/claim", json={"pairingCode": f["pairing"]["pairingCode"]}).status_code == 410
    fresh = f["client"].post("/api/voice/pairing", json={}, headers=f["owner"]).json()
    f["now"][0] += 301
    assert f["client"].post("/api/voice/pairing/claim", json={"pairingCode": fresh["pairingCode"]}).status_code == 410
    assert f["client"].get(f["base"] + "/state", headers={"Authorization": "Bearer mr_dev_" + "f" * 64}).status_code == 404
    assert f["client"].get(f["base"] + "/state").status_code == 401
    assert f["client"].put(f["base"] + "/state", json=f["state"], headers=f["owner"]).status_code == 403


def test_idempotent_submit_rejects_changed_payload_and_invalid_guards(relay):
    f = relay; cmd = f["command"]()
    first = f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    assert first.status_code == 200 and first.json()["duplicate"] is False
    assert f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"]).json()["duplicate"] is True
    assert f["client"].post(f["base"] + "/commands", json={**cmd, "args": {"text": "different"}}, headers=f["owner"]).status_code == 409
    assert f["client"].post(f["base"] + "/commands", json=f["command"](expectedProjectRevision=2), headers=f["owner"]).status_code == 409
    assert f["client"].post(f["base"] + "/commands", json=f["command"](projectSessionId="old-project"), headers=f["owner"]).status_code == 409
    assert f["client"].post(f["base"] + "/commands", json=f["command"](sessionId=str(uuid.uuid4())), headers=f["owner"]).status_code == 400
    assert f["client"].post(f["base"] + "/commands", json=f["command"](expiresAt=iso(f["now"][0] + 301)), headers=f["owner"]).status_code == 400


def test_competing_connections_claim_exactly_once_and_running_never_replays(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    second_store = Store(f["settings"].data_dir, PASSWORD, lambda: f["now"][0])
    try:
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda store: store.relay("poll", f["native_actor"], f["sid"]), (f["store"], second_store)))
        assert sum(r["command"] is not None for r in results) == 1
        f["now"][0] += 20
        paused = second_store.relay("poll", f["native_actor"], f["sid"])
        assert paused["browserConnected"] is False and paused["command"] is None
        f["store"].relay("presence", f["browser_actor"], f["sid"])
        assert second_store.relay("poll", f["native_actor"], f["sid"])["command"] is None
        assert second_store.relay("get_command", f["native_actor"], f["sid"], {"commandId": cmd["commandId"]})["status"] == "running"
    finally: second_store.close()


def test_capture_ready_and_emergency_stop_bypass_running_command(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    f["client"].get(f["base"] + "/poll", headers=f["native"])
    capture = {**f["state"], "state": {"captureId": "capture-one", "recordingPhase": "awaiting_ready"}}
    f["client"].put(f["base"] + "/state", json=capture, headers=f["native"])
    assert f["client"].post(f["base"] + "/capture-ready", json={"captureId": "old"}, headers=f["owner"]).status_code == 409
    assert f["client"].post(f["base"] + "/capture-ready", json={"captureId": "capture-one"}, headers=f["owner"]).status_code == 200
    poll = f["client"].get(f["base"] + "/poll", headers=f["native"]).json()
    assert poll["command"] is None and poll["captureReadyId"] == "capture-one"
    assert f["client"].post(f["base"] + "/emergency-stop", json={"captureId": "old"}, headers=f["owner"]).status_code == 409
    assert f["client"].post(f["base"] + "/emergency-stop", json={"captureId": "capture-one"}, headers=f["owner"]).status_code == 200
    poll = f["client"].get(f["base"] + "/poll", headers=f["native"]).json()
    assert poll["stopRequested"] is True and poll["cancelCaptureId"] == "capture-one" and poll["captureReadyId"] is None
    assert f["client"].post(f["base"] + "/capture-ready", json={"captureId": "capture-one"}, headers=f["owner"]).status_code == 409
    f["client"].put(f["base"] + "/state", json=f["state"], headers=f["native"])
    assert f["client"].get(f["base"] + "/poll", headers=f["native"]).json()["stopRequested"] is False


def test_terminal_results_are_idempotent_and_do_not_rollback_state(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    f["client"].get(f["base"] + "/poll", headers=f["native"])
    newer = {**f["state"], "projectRevision": 2, "state": {"projectName": "newer"}}
    f["client"].put(f["base"] + "/state", json=newer, headers=f["native"])
    result = {"commandId": cmd["commandId"], "status": "succeeded", "message": "Verified on Mac", "state": {"projectName": "older"}, "details": {"nativeStatus": "verified", "planningMs": 30}}
    assert f["client"].post(f["base"] + "/results", json=result, headers=f["native"]).json()["duplicate"] is False
    assert f["client"].post(f["base"] + "/results", json=result, headers=f["native"]).json()["duplicate"] is True
    assert f["client"].post(f["base"] + "/results", json={**result, "message": "changed"}, headers=f["native"]).status_code == 409
    state = f["client"].get(f["base"] + "/state", headers=f["owner"]).json()
    assert state["projectRevision"] == 2 and state["state"]["projectName"] == "newer"
    assert f["client"].put(f["base"] + "/state", json=f["state"], headers=f["native"]).status_code == 409


@pytest.mark.parametrize("change", ["expired", "revision", "project"])
def test_poll_rejects_expired_or_stale_queued_work(relay, change):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    if change == "expired": f["now"][0] += 121
    else:
        update = {**f["state"], **({"projectRevision": 2} if change == "revision" else {"projectSessionId": "project-two"})}
        f["client"].put(f["base"] + "/state", json=update, headers=f["native"])
    assert f["client"].get(f["base"] + "/poll", headers=f["native"]).json()["command"] is None
    saved = f["client"].get(f["base"] + "/commands/" + cmd["commandId"], headers=f["owner"]).json()
    assert saved["status"] == ("expired" if change == "expired" else "rejected") and saved["result"]


def test_browser_absence_pauses_queue_and_revocation_blocks_native(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    f["now"][0] += 16
    assert f["client"].get(f["base"] + "/poll", headers=f["native"]).json()["command"] is None
    assert f["client"].get(f["base"] + "/commands/" + cmd["commandId"], headers=f["owner"]).json()["status"] == "queued"
    assert f["client"].delete(f["base"], headers=f["owner"]).status_code == 200
    assert f["client"].get(f["base"] + "/poll", headers=f["native"]).status_code == 404
    assert f["client"].get(f["base"] + "/state", headers=f["owner"]).status_code == 410
    assert f["client"].post("/api/voice/speech/token", json={"sessionId": f["sid"]}, headers=f["owner"]).status_code == 410
    assert f["provider_calls"] == []


def test_state_and_context_allowlists_and_action_bounds(relay):
    f = relay
    state = {"projectName": "Demo", "local_path": "/tmp/private", "apiKey": "private", "audioData": "bytes", "notes": [{"id": "n1", "text": "note", "projectId": "p1", "trackId": 2}], "tracks": [{"id": 2, "name": "voice", "filePath": "/tmp/private"}]}
    f["client"].put(f["base"] + "/state", json={**f["state"], "state": state}, headers=f["native"])
    stored = f["client"].get(f["base"] + "/state", headers=f["owner"]).json()["state"]
    assert "private" not in json.dumps(stored) and stored["notes"][0]["trackId"] == 2
    for args in ({"type": "shell.exec", "arguments": {}}, {"type": "recording.start", "arguments": {"duration_seconds": 61}}, {"type": "recording.start", "arguments": {"duration_seconds": True}}):
        assert f["client"].post(f["base"] + "/commands", json=f["command"](kind="session_action", args=args), headers=f["owner"]).status_code == 400
    assert sanitize_context({"authorizationToken": "secret", "nested": {"file_path": "/tmp/private", "text": "ordinary"}}) == {"nested": {"text": "ordinary"}}


def test_speech_token_and_stream_are_authenticated_and_keep_provider_key_private(relay):
    f = relay
    body = {"sessionId": f["sid"]}
    assert f["client"].post("/api/voice/speech/token", json=body, headers=f["native"]).status_code == 403
    response = f["client"].post("/api/voice/speech/token", json=body, headers=f["owner"])
    assert response.json()["token"] == "one-use-token" and "test-private-key" not in response.text
    audio = f["client"].post("/api/voice/speech/tts", json={**body, "text": "Ready"}, headers=f["owner"])
    assert audio.content == b"test-mp3-frames" and audio.headers["content-type"] == "audio/mpeg"
    assert all(r.headers["xi-api-key"] == "test-private-key" for r in f["provider_calls"])
    assert f["store"].db.execute("SELECT count(*) FROM commands").fetchone()[0] == 0


def test_planning_rechecks_revision_and_strips_context_secrets(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    payload = {"commandId": cmd["commandId"], "request": {"original_request": "note", "local_path": "/tmp/private", "api_key": "secret"}, "sessionState": {"projectName": "Demo"}}
    assert f["client"].post(f["base"] + "/planner", json=payload, headers=f["native"]).status_code == 409
    f["client"].get(f["base"] + "/poll", headers=f["native"])
    assert f["client"].post(f["base"] + "/planner", json=payload, headers=f["owner"]).status_code == 403
    response = f["client"].post(f["base"] + "/planner", json=payload, headers=f["native"])
    assert response.status_code == 200 and response.json()["kind"] == "session_action"
    assert f["plans"][0][0]["request"] == {"original_request": "note"}
    assert f["client"].post(f["base"] + "/planner", json=payload, headers=f["native"]).status_code == 200
    assert len(f["plans"]) == 1  # The repeated request returns its saved provider result.
    changed = {**payload, "request": {"original_request": "different intent"}}
    assert f["client"].post(f["base"] + "/planner", json=changed, headers=f["native"]).status_code == 409
    f["client"].post(f["base"] + "/results", json={"commandId": cmd["commandId"], "status": "succeeded", "message": "Saved note"}, headers=f["native"])
    second = f["command"]()
    f["client"].post(f["base"] + "/commands", json=second, headers=f["owner"])
    f["client"].get(f["base"] + "/poll", headers=f["native"])
    f["during_plan"] = lambda: f["store"].relay("put_state", f["native_actor"], f["sid"], {**f["state"], "projectRevision": 2})
    assert f["client"].post(f["base"] + "/planner", json={**payload, "commandId": second["commandId"]}, headers=f["native"]).status_code == 409


def test_invalid_native_cannot_create_planner_rate_buckets(relay):
    f = relay
    before = f["store"].db.execute("SELECT count(*) FROM rate_limits").fetchone()[0]
    response = f["client"].post(f["base"] + "/planner", headers={"Authorization": "Bearer mr_dev_" + "f" * 64},
                                json={"commandId": str(uuid.uuid4()), "request": {}, "sessionState": {}})
    assert response.status_code == 404
    assert f["store"].db.execute("SELECT count(*) FROM rate_limits").fetchone()[0] == before


@pytest.mark.parametrize("route", ["token", "tts"])
def test_revocation_during_provider_wait_prevents_new_speech_access(relay, route):
    f = relay
    f["during_speech"] = lambda: f["store"].relay("revoke", f["browser_actor"], f["sid"])
    response = f["client"].post("/api/voice/speech/" + route, json={"sessionId": f["sid"], "text": "Ready"}, headers=f["owner"])
    assert response.status_code == 410
    assert "one-use-token" not in response.text and "test-mp3-frames" not in response.text


def test_concurrent_planner_claim_is_durable_and_does_not_restart(relay):
    f = relay; cmd = f["command"]()
    f["client"].post(f["base"] + "/commands", json=cmd, headers=f["owner"])
    f["client"].get(f["base"] + "/poll", headers=f["native"])
    identity = {"commandId": cmd["commandId"], "operation": "planner", "requestHash": digest("request")}
    second_store = Store(f["settings"].data_dir, PASSWORD, lambda: f["now"][0])
    def claim(store):
        try: return store.relay("plan_begin", f["native_actor"], f["sid"], identity)
        except RelayError as error: return error.code
    try:
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(claim, (f["store"], second_store)))
        assert results.count({"cached": False}) == 1 and results.count("planning_in_progress") == 1
        result = {"httpStatus": 200, "response": {"kind": "clarify", "message": "Which vocal?"}}
        f["store"].relay("plan_finish", f["native_actor"], f["sid"], {**identity, "result": result})
        assert second_store.relay("plan_begin", f["native_actor"], f["sid"], identity) == {"cached": True, "result": result}
    finally: second_store.close()


def test_password_rotation_revokes_existing_owner_and_native_tokens(relay):
    f = relay
    replacement = Store(f["settings"].data_dir, "rotated-owner-test-password", lambda: f["now"][0])
    try:
        with pytest.raises(RelayError) as old: replacement.authenticate_owner(f["owner_token"])
        assert old.value.status == 401
        with pytest.raises(RelayError) as device: replacement.relay("get_state", f["native_actor"], f["sid"])
        assert device.value.status == 404
        assert replacement.login("rotated-owner-test-password")["user"]["id"] == "owner"
    finally: replacement.close()


def test_retention_and_restart_preserve_running_commands(tmp_path):
    now = [time.time()]
    store = Store(str(tmp_path), PASSWORD, lambda: now[0])
    owner = {"owner": True}; device = {"device_hash": digest("test-device")}
    sid = store.relay("pairing_create", owner, payload={"code_hash": digest("code")})["sessionId"]
    store.relay("pairing_claim", payload={"code_hash": digest("code"), "device_hash": device["device_hash"], "device_name": "Mac"})
    store.relay("put_state", device, sid, {"projectSessionId": "project", "projectRevision": 1, "state": {}})
    command = {"version": 1, "commandId": str(uuid.uuid4()), "sessionId": sid, "projectSessionId": "project", "expectedProjectRevision": 1, "kind": "utterance", "args": {"text": "edit"}, "expiresAt": iso(now[0] + 120)}
    store.relay("submit", owner, sid, {"envelope": command})
    store.relay("poll", device, sid); store.close()
    reopened = Store(str(tmp_path), PASSWORD, lambda: now[0])
    try:
        assert reopened.relay("poll", device, sid)["command"] is None
        assert reopened.relay("get_command", owner, sid, {"commandId": command["commandId"]})["status"] == "running"
        now[0] += 7 * 86400 + 1
        assert reopened.cleanup() == 1
    finally: reopened.close()


def test_health_starts_without_provider_keys_but_rejects_weak_owner_password(tmp_path):
    with TestClient(create_app(Settings(password=PASSWORD, data_dir=str(tmp_path)))) as client:
        assert client.get("/health").status_code == 200
    with pytest.raises(RuntimeError, match="at least 12"):
        with TestClient(create_app(Settings(password="weak", data_dir=str(tmp_path)))): pass
