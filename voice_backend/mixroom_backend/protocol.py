"""Bounded protocol validation. Never forwards project files or arbitrary actions."""
import hashlib
import json
import math
import re
import secrets
import time
from datetime import datetime, timezone


class RelayError(Exception):
    def __init__(self, status: int, code: str, message: str = ""):
        self.status, self.code, self.message = status, code, message or code.replace("_", " ")
        super().__init__(self.message)


def fail(status, code, message=""):
    raise RelayError(status, code, message)


def obj(value, label="body"):
    if not isinstance(value, dict):
        fail(400, "invalid_payload", f"{label} must be an object")
    return value


def text(value, label, maximum=256):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        fail(400, "invalid_payload", f"{label} is required (maximum {maximum} characters)")
    return value


def uuid(value, label):
    value = text(value, label, 36)
    if not re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", value):
        fail(400, "invalid_payload", f"{label} must be a UUID")
    return value.lower()


def revision(value):
    if type(value) is not int or not 0 <= value <= 9_007_199_254_740_991:
        fail(400, "invalid_revision", "Project revision must be a nonnegative safe integer")
    return value


def iso(timestamp):
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def timestamp(value):
    try:
        parsed = datetime.fromisoformat(text(value, "expiresAt", 40).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError()
        return parsed.timestamp()
    except (ValueError, OverflowError):
        fail(400, "invalid_expiry")


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def token(prefix):
    return prefix + secrets.token_hex(32)


def pairing_code():
    return "".join(secrets.choice("23456789ABCDEFGHJKLMNPQRSTUVWXYZ") for _ in range(12))


def normalize_code(value):
    value = re.sub(r"[\s-]", "", text(value, "pairingCode", 32)).upper()
    if not re.fullmatch(r"[2-9A-HJ-NP-Z]{12}", value):
        fail(400, "invalid_pairing", "Pairing code must contain 12 characters")
    return value


SESSION_ACTIONS = {"recording.start", "recording.stop", "comparison.before", "comparison.after", "comparison.keep_before",
                   "comparison.keep_after", "history.undo", "history.redo", "notes.add", "notes.list", "notes.complete"}


def validate_action(value):
    action = obj(value, "action")
    kind = text(action.get("type"), "action.type", 80)
    if kind not in SESSION_ACTIONS:
        fail(400, "unsupported_action")
    args, clean = obj(action.get("arguments", {}), "action.arguments"), {}
    if kind == "notes.add": clean["text"] = text(args.get("text"), "note text", 2000)
    if kind == "notes.complete": clean["note_id"] = text(args.get("note_id"), "note_id", 128)
    if kind == "recording.start":
        if "duration_seconds" in args and "bars" in args:
            fail(400, "invalid_capture", "Choose duration_seconds or bars, not both")
        for key, maximum in (("duration_seconds", 60), ("bars", 128)):
            if key in args:
                value = args[key]
                if type(value) not in (int, float) or not math.isfinite(value) or not 1 <= value <= maximum:
                    fail(400, "invalid_capture", f"{key} is out of range")
                clean[key] = value
        if "row_id" in args: clean["row_id"] = revision(args["row_id"])
        if "hum" in args:
            if type(args["hum"]) is not bool: fail(400, "invalid_capture", "hum must be boolean")
            clean["hum"] = args["hum"]
        if "instrument_id" in args: clean["instrument_id"] = text(args["instrument_id"], "instrument_id", 128)
    return {"type": kind, "arguments": clean}


def validate_command(value, session_id, now=None):
    body = obj(value)
    if type(body.get("version")) is not int or body["version"] != 1: fail(400, "unsupported_version")
    if uuid(body.get("sessionId"), "sessionId") != session_id: fail(400, "session_mismatch")
    expiry = timestamp(body.get("expiresAt"))
    if expiry > (time.time() if now is None else now) + 300: fail(400, "invalid_expiry")
    # Old identical retries still resolve from their saved command before expiry checks.
    kind, args = body.get("kind"), obj(body.get("args"), "args")
    if kind not in ("utterance", "session_action"): fail(400, "unsupported_kind")
    return {"version": 1, "commandId": uuid(body.get("commandId"), "commandId"), "sessionId": session_id,
            "projectSessionId": text(body.get("projectSessionId"), "projectSessionId", 128),
            "expectedProjectRevision": revision(body.get("expectedProjectRevision")), "kind": kind,
            "args": {"text": text(args.get("text"), "text", 4000)} if kind == "utterance" else validate_action(args), "expiresAt": iso(expiry)}


def pick(source, strings=(), booleans=(), numbers=()):
    clean = {}
    for key in strings:
        if isinstance(source.get(key), str): clean[key] = source[key][:2000]
    for key in booleans:
        if type(source.get(key)) is bool: clean[key] = source[key]
    for key in numbers:
        if type(source.get(key)) in (int, float) and math.isfinite(source[key]) and -1e9 <= source[key] <= 1e9:
            clean[key] = source[key]
    return clean


def sanitize_state(value):
    state = obj(value, "state")
    clean = pick(state, ("projectName", "captureId", "recordingPhase", "error"), ("busy", "inputReady", "projectReady"), ("captureRemainingSeconds",))
    if state.get("transport") is not None:
        clean["transport"] = pick(obj(state["transport"]), ("timeSignature",), ("playing", "recording", "loopEnabled"), ("positionSeconds", "tempo", "loopStartSeconds", "loopEndSeconds"))
    if isinstance(state.get("tracks"), list):
        clean["tracks"] = [{**pick(obj(t), ("name", "type"), ("muted", "solo", "armed"), ("volumeDb", "pan")), "id": revision(t.get("id"))} for t in state["tracks"][:256]]
    if isinstance(state.get("selectedTrackIds"), list): clean["selectedTrackIds"] = [revision(v) for v in state["selectedTrackIds"][:256]]
    if state.get("comparison") is not None: clean["comparison"] = pick(obj(state["comparison"]), ("id", "side"), ("available",))
    if isinstance(state.get("notes"), list): clean["notes"] = [pick(obj(n), ("id", "text", "projectId"), ("completed",), ("playheadMs", "trackId")) for n in state["notes"][:100]]
    if state.get("lastResult") is not None: clean["lastResult"] = pick(obj(state["lastResult"]), ("status", "message"))
    return clean


def sanitize_context(value, depth=0):
    if depth > 12: fail(400, "context_too_deep")
    if isinstance(value, list): return [sanitize_context(v, depth + 1) for v in value[:512]]
    if isinstance(value, dict):
        return {key: sanitize_context(v, depth + 1) for key, v in value.items()
                if not re.search(r"path|token|secret|password|credential|audio.?data|audio.?base64|file.?data|file.?bytes|api.?key", key, re.I)}
    if isinstance(value, str):
        if re.match(r"^(file://|/(Users|home|private|tmp|var|Volumes|mnt|opt|etc|root)/|[A-Za-z]:\\)", value): return "[local value omitted]"
        return value[:8000]
    return value
