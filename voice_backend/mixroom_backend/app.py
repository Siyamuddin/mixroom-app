"""Local FastAPI transport for the unchanged MixRoom voice protocol."""
import asyncio
from contextlib import asynccontextmanager, suppress
from email.utils import formatdate
import json
import re
import time
from urllib.parse import quote

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, Response, StreamingResponse
import httpx

from .config import Settings
from .protocol import RelayError, canonical, digest, fail, iso, normalize_code, obj, pairing_code, revision, sanitize_context, sanitize_state, text, token, uuid, validate_action, validate_command
from .store import Store


async def _default_planner(payload, settings):
    from planner.bridge import plan_voice_request
    return await plan_voice_request(payload, settings)


async def _default_mix(payload, settings):
    from planner.bridge import resolve_mix_request
    return await resolve_mix_request(payload, settings)


def error_response(error):
    return JSONResponse({"error": {"code": error.code, "message": error.message}}, status_code=error.status)


def create_app(settings=None, *, provider_transport=None, planner=None, mix_resolver=None, clock=time.time):
    settings = settings or Settings.from_env()
    plan_voice, plan_mix = planner or _default_planner, mix_resolver or _default_mix

    @asynccontextmanager
    async def lifespan(app):
        settings.validate()
        app.state.store = Store(settings.data_dir, settings.password, clock)
        app.state.http = httpx.AsyncClient(timeout=httpx.Timeout(30, connect=10), follow_redirects=False, transport=provider_transport)

        async def retention():
            while True:
                await asyncio.sleep(3600)
                app.state.store.cleanup()

        cleanup_task = asyncio.create_task(retention())
        try:
            yield
        finally:
            cleanup_task.cancel()
            with suppress(asyncio.CancelledError): await cleanup_task
            await app.state.http.aclose()
            app.state.store.close()

    app = FastAPI(title="MixRoom local voice relay", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def headers_and_errors(request, call_next):
        origin = request.headers.get("origin")
        allowed = origin is None or origin in settings.allowed_origins
        try:
            if not allowed: fail(403, "origin_not_allowed", "This browser origin is not allowed")
            response = Response(status_code=204) if request.method == "OPTIONS" else await call_next(request)
        except RelayError as error:
            response = error_response(error)
        except Exception:
            # No upstream response body, credential, filesystem path, or stack trace.
            response = error_response(RelayError(503, "relay_unavailable", "Relay request failed; check command status before retrying"))
        response.headers.update({"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Date": formatdate(clock(), usegmt=True), "Vary": "Origin"})
        if origin and allowed:
            response.headers.update({"Access-Control-Allow-Origin": origin, "Access-Control-Allow-Headers": "authorization,content-type,apikey,x-client-info",
                                     "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS", "Access-Control-Expose-Headers": "Date"})
            if request.headers.get("access-control-request-private-network") == "true":
                response.headers["Access-Control-Allow-Private-Network"] = "true"
        return response

    @app.exception_handler(RelayError)
    async def relay_error(_request, error):
        return error_response(error)

    async def body(request, limit=96 * 1024):
        if not request.headers.get("content-type", "").lower().startswith("application/json"): fail(415, "json_required")
        try:
            if int(request.headers.get("content-length", "0")) > limit: fail(413, "body_too_large")
        except ValueError: fail(400, "invalid_content_length")
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > limit: fail(413, "body_too_large")
            chunks.append(chunk)
        try:
            def invalid_constant(_value): raise ValueError()
            return obj(json.loads(b"".join(chunks), parse_constant=invalid_constant))
        except (ValueError, UnicodeDecodeError): fail(400, "invalid_json")

    def authenticate(request):
        match = re.fullmatch(r"Bearer (\S+)", request.headers.get("authorization", ""), re.I)
        if not match: fail(401, "auth_required")
        bearer = match[1]
        if bearer.startswith("mr_dev_"):
            if not re.fullmatch(r"mr_dev_[0-9a-f]{64}", bearer): fail(401, "invalid_device_token")
            return {"device_hash": digest(bearer)}
        if not re.fullmatch(r"mr_owner_[0-9a-f]{64}", bearer): fail(401, "invalid_user_token", "Sign in again to continue")
        return request.app.state.store.authenticate_owner(bearer)

    def browser(actor):
        if not actor.get("owner"): fail(403, "browser_auth_required")

    def native(actor):
        if not actor.get("device_hash"): fail(403, "device_auth_required")

    @app.get("/", response_class=HTMLResponse)
    async def service_home():
        return HTMLResponse("""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>MixRoom backend</title><style>
body{margin:0;background:#111315;color:#f4f4f1;font:17px/1.6 system-ui,sans-serif}
main{max-width:36rem;margin:12vh auto;padding:2rem}h1{font-size:2rem;line-height:1.2}
p{color:#bfc4c7}a{color:#a5e5c3;text-underline-offset:.2em}nav{display:flex;gap:1.5rem;flex-wrap:wrap}
</style></head><body><main><h1>MixRoom backend is running</h1>
<p>Open the MixRoom app to sign in and pair your desktop session.</p>
<nav aria-label="MixRoom links"><a href="http://127.0.0.1:5173/">Open MixRoom</a><a href="/health">View service health</a></nav>
</main></body></html>""", headers={"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"})

    @app.get("/health")
    @app.get("/api/voice/health")
    async def health():
        return {"ok": True, "protocolVersion": 1}

    @app.post("/api/auth/login")
    async def login(request: Request):
        store = request.app.state.store
        store.rate("login-global", 20)
        # Ignore forwarded headers: the loopback service should not trust proxy identities.
        store.rate("login:" + digest(request.client.host if request.client else "unknown"), 5)
        payload = await body(request, 8192)
        return store.login(text(payload.get("password"), "password", 4096))

    @app.get("/api/auth/status")
    async def auth_status(request: Request):
        actor = authenticate(request); browser(actor)
        return {"user": {"id": "owner"}, "expiresAt": iso(actor["expires_at"])}

    @app.post("/api/auth/logout")
    async def logout(request: Request):
        actor = authenticate(request); browser(actor)
        return request.app.state.store.logout(actor)

    async def provider_json(response):
        if response.status_code < 200 or response.status_code >= 300: fail(502, "provider_failed", "Voice provider request failed")
        if len(response.content) > 512 * 1024: fail(502, "provider_response_too_large")
        try: return obj(response.json(), "provider response")
        except (ValueError, RelayError): fail(502, "invalid_provider_response")

    async def speech(request, route, actor):
        browser(actor)
        payload = await body(request)
        sid = uuid(payload.get("sessionId"), "sessionId")
        store, http = request.app.state.store, request.app.state.http
        state = store.relay("get_state", actor, sid)
        if state["status"] != "active": fail(409, "device_not_ready", "Pair the native device first")
        if not settings.elevenlabs_api_key: fail(503, "speech_not_configured", "Configure the server ElevenLabs key")
        if route == "speech/token":
            store.rate("speech-token:" + sid, 30)
            response = await http.post("https://api.elevenlabs.io/v1/single-use-token/realtime_scribe", headers={"xi-api-key": settings.elevenlabs_api_key})
            data = await provider_json(response)
            # Revocation/logout may have completed while the provider was working.
            store.relay("get_state", authenticate(request), sid)
            return {"token": text(data.get("token"), "token", 8192), "expiresInSeconds": 900}
        store.rate("speech-tts:" + sid, 30)
        spoken_text = text(payload.get("text"), "text", 2000)
        if not settings.elevenlabs_voice_id: fail(503, "speech_not_configured", "Configure the server ElevenLabs voice")
        upstream = http.build_request("POST", f"https://api.elevenlabs.io/v1/text-to-speech/{quote(settings.elevenlabs_voice_id, safe='')}/stream?output_format=mp3_44100_128",
                                      headers={"xi-api-key": settings.elevenlabs_api_key}, json={"text": spoken_text, "model_id": settings.elevenlabs_tts_model})
        response = await http.send(upstream, stream=True)
        if not 200 <= response.status_code < 300:
            await response.aclose()
            fail(502, "speech_unavailable", "Speech generation failed")
        try:
            store.relay("get_state", authenticate(request), sid)
        except BaseException:
            await response.aclose()
            raise

        async def audio_bytes():
            size = 0
            try:
                async for chunk in response.aiter_bytes():
                    size += len(chunk)
                    if size > 12_000_000: return
                    yield chunk
            finally:
                await response.aclose()

        return StreamingResponse(audio_bytes(), media_type="audio/mpeg")

    async def plan(request, route, actor, sid):
        native(actor)
        payload = await body(request, 4_600_000)
        command_id = uuid(payload.get("commandId"), "commandId")
        store = request.app.state.store
        store.relay("authorize_command", actor, sid, {"commandId": command_id})
        store.rate(route + ":" + sid, 20)
        if route == "planner":
            provider_input = {"sessionId": sid, "commandId": command_id, "request": sanitize_context(obj(payload.get("request"), "request")),
                              "sessionState": sanitize_state(payload.get("sessionState", {}))}
        else:
            provider_input = sanitize_context(obj(payload.get("payload"), "payload"))
        request_hash = digest(canonical(provider_input))
        # A DAW plan may contain several distinct local mix operations. Primary
        # voice planning has one immutable request; mix resolution keys each body.
        cache_operation = route if route == "planner" else route + ":" + request_hash
        identity = {"commandId": command_id, "operation": cache_operation, "requestHash": request_hash}
        saved = store.relay("plan_begin", actor, sid, identity)
        if saved["cached"]:
            result = saved["result"]
        else:
            try:
                result = await (plan_voice(provider_input, settings) if route == "planner" else plan_mix(provider_input, settings))
                # Persist failures too: repeating an uncertain provider call for the
                # same command can spend credits and produce a different plan.
                if not isinstance(result, dict) or type(result.get("httpStatus")) is not int:
                    result = {"httpStatus": 502, "response": {"error": {"code": "invalid_plan"}}}
                store.relay("plan_finish", actor, sid, {**identity, "result": sanitize_context(result)})
            except BaseException:
                with suppress(Exception):
                    store.relay("plan_finish", actor, sid, {**identity, "result": {"httpStatus": 503, "response": {"error": {"code": "planning_interrupted"}}}})
                raise
        if not isinstance(result, dict) or type(result.get("httpStatus")) is not int: fail(502, "invalid_plan")
        if not 200 <= result["httpStatus"] < 300:
            fail(result["httpStatus"] if 400 <= result["httpStatus"] < 600 else 502, "planning_failed", "The planning service could not complete this request")
        data = obj(result.get("response"), "planner response")
        store.relay("authorize_command", actor, sid, {"commandId": command_id})
        if route == "mix-resolve": return sanitize_context(data)
        diagnostics = {"diagnostics": sanitize_context(obj(data["diagnostics"]))} if data.get("diagnostics") else {}
        if data.get("kind") == "daw_plan": return {"kind": "daw_plan", "response": sanitize_context(obj(data.get("response"))), **diagnostics}
        if data.get("kind") == "session_action": return {"kind": "session_action", "action": validate_action(data.get("action")), **diagnostics}
        if data.get("kind") in ("clarify", "respond", "unsupported"):
            return {"kind": data["kind"], "message": text(data.get("message"), "message", 4000), **diagnostics}
        fail(502, "invalid_plan")

    @app.api_route("/api/voice/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
    async def voice(request: Request, path: str):
        store = request.app.state.store
        route, method = path.rstrip("/"), request.method
        if route == "pairing/claim" and method == "POST":
            store.rate("pair-claim-global", 300)
            store.rate("pair-claim:" + digest(request.client.host if request.client else "unknown"), 10)
            payload = await body(request)
            code, bearer = normalize_code(payload.get("pairingCode")), token("mr_dev_")
            result = store.relay("pairing_claim", payload={"code_hash": digest(code), "device_hash": digest(bearer), "device_name": text(payload.get("deviceName", "MixRoom desktop"), "deviceName", 80)})
            return {**result, "deviceToken": bearer}
        actor = authenticate(request)
        if route == "pairing" and method == "POST":
            browser(actor); store.rate("pair-create:owner", 5, 60)
            store.cleanup()
            code = pairing_code()
            result = store.relay("pairing_create", actor, payload={"code_hash": digest(code)})
            return JSONResponse({**result, "pairingCode": "-".join(code[i:i + 4] for i in range(0, 12, 4))}, status_code=201)
        if route in ("speech/token", "speech/tts") and method == "POST": return await speech(request, route, actor)
        match = re.fullmatch(r"sessions/([^/]+)(?:/(.*))?", route)
        if not match: fail(404, "not_found")
        sid, operation = uuid(match[1], "sessionId"), match[2] or ""
        if not operation and method == "DELETE":
            browser(actor); return store.relay("revoke", actor, sid)
        if operation == "state" and method == "GET": return store.relay("get_state", actor, sid)
        if operation == "state" and method == "PUT":
            native(actor); payload = await body(request)
            return store.relay("put_state", actor, sid, {"projectSessionId": text(payload.get("projectSessionId"), "projectSessionId", 128),
                                                       "projectRevision": revision(payload.get("projectRevision")), "state": sanitize_state(payload.get("state"))})
        if operation == "presence" and method == "POST":
            browser(actor); return store.relay("presence", actor, sid)
        if operation == "capture-ready" and method == "POST":
            browser(actor); payload = await body(request)
            return store.relay("capture_ready", actor, sid, {"captureId": text(payload.get("captureId"), "captureId", 128)})
        if operation == "emergency-stop" and method == "POST":
            browser(actor); payload = await body(request)
            return store.relay("emergency_stop", actor, sid, {} if "captureId" not in payload else {"captureId": text(payload["captureId"], "captureId", 128)})
        if operation == "poll" and method == "GET":
            native(actor); return store.relay("poll", actor, sid)
        if operation == "commands" and method == "POST":
            browser(actor); command = validate_command(await body(request), sid, clock())
            store.rate("commands:" + sid, 60)
            return store.relay("submit", actor, sid, {"envelope": command})
        if operation.startswith("commands/") and method == "GET":
            return store.relay("get_command", actor, sid, {"commandId": uuid(operation[9:], "commandId")})
        if operation == "results" and method == "POST":
            native(actor); payload = await body(request)
            command_id = uuid(payload.get("commandId"), "commandId")
            if payload.get("status") not in ("succeeded", "failed", "rejected"): fail(400, "invalid_result")
            result = {"commandId": command_id, "status": payload["status"], "message": text(payload.get("message"), "message", 4000)}
            if "state" in payload: result["state"] = sanitize_state(payload["state"])
            if "details" in payload: result["details"] = sanitize_context(obj(payload["details"]))
            return store.relay("result", actor, sid, {"commandId": command_id, "result": result})
        if operation in ("planner", "mix-resolve") and method == "POST": return await plan(request, operation, actor, sid)
        fail(404, "not_found", "Unknown route or unsupported method")

    return app


app = create_app()
