#!/usr/bin/env python3
"""Explicit live-provider planner smoke through the running local API.

Run with --live. This spends OpenAI credits (and Jev credits if configured).
The fixture never connects a microphone or executes a native DAW action. It
rejects each fixture command after inspecting its plan, then revokes the session.
Only sanitized validation summaries are printed; keys and bearer tokens are not.
"""
import argparse
from contextlib import suppress
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import sys
import time
import uuid
from urllib.parse import urlsplit

from dotenv import dotenv_values
import httpx

CASES = {
    "volume": "Lower the Vocal track by exactly two decibels.",
    "before": "Let me hear the before version of the current comparison.",
    "after": "Let me hear the after version of the current comparison.",
    "record": "Record the selected Vocal track for ten seconds.",
    "hum": "Record me humming for ten seconds, then turn it into a piano melody using Warm Keys.",
    "hum_natural": "Let me hum for ten seconds and hear it on Warm Keys.",
    "hum_default": "Record ten seconds of my humming and convert that take into an instrument melody.",
    "mixed_capture_edit": "Record me humming for ten seconds using Warm Keys, and also lower the Vocal track by two decibels.",
    "note": "Add a session note: bring up the chorus vocal on the next pass.",
}


def fixture(utterance, project_id):
    """The minimal valid native V3 context used by canonical worker tests."""
    return {
        "request_contract": "mixroom_v3_context_v2", "original_request": utterance,
        "conversation": [], "plan_schema_version": "plan_v3_prototype_2",
        "supported_command_types": ["row.adjust_gain_db", "transport.set_playing"], "resource_refs_enabled": False,
        "core_context": {
            "schema_version": "core_context_v3_prototype_1", "profile": "essential", "request_mode": "new_request", "state_digest": "live-fixture-revision-one",
            "project": {"project_id": project_id, "bpm": 120, "beats_per_bar": 4, "beat_unit": 4, "row_capacity": {"current_rows": 1, "max_rows": 8}},
            "transport": {"playing": False, "recording": False, "metronome_enabled": False, "loop_enabled": False, "loop_start_ms": 0, "loop_end_ms": 0},
            "selection": {}, "rows": [{"row_id": 2, "name": "Vocal", "lane_kind": "audio", "gain_db": 0, "pan_signed": 0, "mix_processing_supported": True, "effects": [], "automation_targets": []}],
            "clips": [], "groups": [], "master": {}, "effects": [], "library_assets": [],
            "instruments": ["mixroom.warm_keys"], "instrument_catalog": [{"instrument_id": "mixroom.warm_keys", "name": "Warm Keys"}], "runtime_capabilities": [],
        },
    }


class SmokeFailure(Exception):
    def __init__(self, code, status=None):
        self.code, self.status = code, status
        super().__init__(code)


def checked(response):
    if response.status_code >= 400:
        code = "request_failed"
        try:
            supplied = response.json().get("error", {}).get("code", "")
            if isinstance(supplied, str) and re.fullmatch(r"[a-z0-9_]{1,80}", supplied): code = supplied
        except (ValueError, AttributeError): pass
        raise SmokeFailure(code, response.status_code)
    return response.json()


def validate(case, result):
    case = "hum" if case.startswith("hum") else case
    kind = result.get("kind")
    if case == "mixed_capture_edit":
        if kind != "clarify" or "action" in result: raise SmokeFailure("mixed_request_must_clarify")
        return {"kind": kind, "no_action": True}
    if case == "volume":
        plan = result.get("response", {}).get("plan", {})
        commands = plan.get("commands", [])
        if kind != "daw_plan" or plan.get("outcome") != "plan" or len(commands) != 1:
            raise SmokeFailure("expected_single_volume_plan")
        change = commands[0]
        args = change.get("arguments", {})
        if change.get("type") != "row.adjust_gain_db" or args.get("row_id") != 2 or args.get("delta_db") != -2:
            raise SmokeFailure("volume_target_or_delta_mismatch")
        return {"kind": kind, "type": change["type"], "row_id": 2, "delta_db": -2}
    action = result.get("action", {})
    args = action.get("arguments", {})
    expected = {"before": "comparison.before", "after": "comparison.after", "record": "recording.start", "hum": "recording.start", "note": "notes.add"}[case]
    if kind != "session_action" or action.get("type") != expected: raise SmokeFailure("session_action_mismatch_" + str(kind))
    facts = {"kind": kind, "type": action["type"]}
    if case in ("record", "hum"):
        if args.get("duration_seconds") != 10 or "bars" in args or args.get("row_id", 2) != 2:
            raise SmokeFailure("recording_duration_or_target_mismatch")
        if bool(args.get("hum", False)) != (case == "hum"): raise SmokeFailure("recording_mode_mismatch")
        facts.update(duration_seconds=10, row_id=args.get("row_id", 2), hum=bool(args.get("hum", False)))
        if case == "hum":
            instrument = args.get("instrument_id", "mixroom.warm_keys")
            if instrument != "mixroom.warm_keys": raise SmokeFailure("humming_instrument_mismatch")
            facts["instrument_id"] = instrument
    if case == "note":
        note = re.sub(r"[^a-z0-9]+", " ", str(args.get("text", "")).casefold()).strip()
        if note != "bring up the chorus vocal on the next pass": raise SmokeFailure("note_content_mismatch")
        facts["note_content_preserved"] = True
    return facts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Explicitly authorize calls to configured real AI providers")
    parser.add_argument("--cases", default=",".join(CASES), help="Comma-separated case names: " + ",".join(CASES))
    parser.add_argument("--report", type=Path, help="Write a sanitized JSON report")
    parser.add_argument("--base-url", default="http://127.0.0.1:8765", help="Local API URL (host fallback currently uses port 8766)")
    parser.add_argument("--speech", action="store_true", help="Also request one ElevenLabs token and one short TTS response")
    args = parser.parse_args()
    if not args.live: parser.error("Pass --live to run the real-provider smoke test.")
    target = urlsplit(args.base_url)
    if target.scheme != "http" or target.hostname not in ("127.0.0.1", "localhost", "::1") or target.username or target.password or target.path not in ("", "/") or target.query or target.fragment:
        parser.error("--base-url must be an HTTP loopback origin")
    selected = args.cases.split(",")
    if not selected or any(case not in CASES for case in selected): parser.error("Unknown case name")
    root = Path(__file__).resolve().parents[1]
    password = dotenv_values(root / ".env").get("MIXROOM_PASSWORD")
    if not password: raise SmokeFailure("owner_password_not_configured")
    report = {"live_provider_calls": True, "api_origin": args.base_url, "native_edit_performed": False, "microphone_used": False, "cases": []}
    owner, route, current_command = None, None, None
    try:
        with httpx.Client(base_url=args.base_url, timeout=90, follow_redirects=False) as client:
            checked(client.get("/health"))
            login = checked(client.post("/api/auth/login", json={"password": password}))
            owner = {"Authorization": "Bearer " + login["access_token"]}
            try:
                pairing = checked(client.post("/api/voice/pairing", json={}, headers=owner))
                sid = pairing["sessionId"]
                route = "/api/voice/sessions/" + sid
                claimed = checked(client.post("/api/voice/pairing/claim", json={"pairingCode": pairing["pairingCode"], "deviceName": "Live planner fixture; no native execution"}))
                native = {"Authorization": "Bearer " + claimed["deviceToken"]}
                project_id = "live-planner-fixture-" + str(uuid.uuid4())
                for case in selected:
                    state = {"projectName": "Live planner fixture — no native edit", "projectReady": True, "selectedTrackIds": [2], "recordingPhase": "idle",
                             "tracks": [{"id": 2, "name": "Vocal", "type": "audio", "volumeDb": 0}], "comparison": {"available": True, "id": "fixture-comparison", "side": "before" if case == "after" else "after"}, "notes": []}
                    checked(client.put(route + "/state", headers=native, json={"projectSessionId": project_id, "projectRevision": 1, "state": state}))
                    current_command = str(uuid.uuid4())
                    envelope = {"version": 1, "commandId": current_command, "sessionId": sid, "projectSessionId": project_id, "expectedProjectRevision": 1,
                                "kind": "utterance", "args": {"text": CASES[case]}, "expiresAt": (datetime.now(timezone.utc) + timedelta(seconds=120)).isoformat()}
                    checked(client.post(route + "/commands", headers=owner, json=envelope))
                    claimed_command = checked(client.get(route + "/poll", headers=native)).get("command")
                    if not claimed_command or claimed_command.get("commandId") != current_command: raise SmokeFailure("fixture_command_not_claimed")
                    started = time.perf_counter()
                    try:
                        result = checked(client.post(route + "/planner", headers=native, json={"commandId": current_command, "request": fixture(CASES[case], project_id), "sessionState": state}))
                        facts = validate(case, result)
                        diagnostics = result.get("diagnostics", {})
                        safe_diagnostics = {key: diagnostics[key] for key in ("backend", "reasoningProvider", "reasoningModel", "jevConfigured", "jevAttempted", "jevRoute", "dawModelCalls") if key in diagnostics}
                        entry = {"case": case, "passed": True, "latency_ms": round((time.perf_counter() - started) * 1000), **facts, "diagnostics": safe_diagnostics}
                    except SmokeFailure as failure:
                        entry = {"case": case, "passed": False, "latency_ms": round((time.perf_counter() - started) * 1000), "error_code": failure.code, "http_status": failure.status}
                    finally:
                        checked(client.post(route + "/results", headers=native, json={"commandId": current_command, "status": "rejected", "message": "Live planner fixture completed. No native action was executed.", "details": {"nativeStatus": "fixture_only"}}))
                        current_command = None
                    report["cases"].append(entry)
                    print(json.dumps(entry), flush=True)
                    # Stop on provider/transport failure instead of spending credits on identical failures.
                    if not entry["passed"] and entry.get("http_status"): break
                if args.speech:
                    started = time.perf_counter()
                    token = checked(client.post("/api/voice/speech/token", headers=owner, json={"sessionId": sid}))
                    if not isinstance(token.get("token"), str) or not token["token"]:
                        raise SmokeFailure("speech_token_missing")
                    del token
                    token_ms = round((time.perf_counter() - started) * 1000)
                    started = time.perf_counter()
                    audio = client.post("/api/voice/speech/tts", headers=owner, json={"sessionId": sid, "text": "MixRoom is ready for your next take."})
                    if audio.status_code >= 400: checked(audio)
                    if not audio.headers.get("content-type", "").startswith("audio/") or len(audio.content) < 1000:
                        raise SmokeFailure("speech_audio_invalid")
                    report["speech"] = {"token_passed": True, "token_latency_ms": token_ms, "tts_passed": True, "tts_latency_ms": round((time.perf_counter() - started) * 1000), "audio_bytes": len(audio.content), "audio_played": False, "audio_saved": False}
                    print(json.dumps({"speech": report["speech"]}), flush=True)
            finally:
                if route:
                    with suppress(Exception): client.delete(route, headers=owner)
                with suppress(Exception): client.post("/api/auth/logout", headers=owner)
    except SmokeFailure as failure:
        report["setup_error"] = {"error_code": failure.code, "http_status": failure.status}
    except (httpx.TransportError, ValueError, KeyError):
        report["setup_error"] = {"error_code": "local_api_unavailable_or_invalid_response"}
    report["passed"] = len(report["cases"]) == len(selected) and all(case["passed"] for case in report["cases"]) and "setup_error" not in report
    if args.report: args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "case_count": len(report["cases"]), "native_edit_performed": False, **({"setup_error": report["setup_error"]} if "setup_error" in report else {})}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    try: sys.exit(main())
    except SmokeFailure as error:
        print(json.dumps({"passed": False, "error_code": error.code, "http_status": error.status})); sys.exit(1)
