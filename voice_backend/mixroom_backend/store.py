"""Durable local relay. Every mutation is a SQLite BEGIN IMMEDIATE transaction."""
from contextlib import contextmanager
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import sqlite3
import threading
import time
import uuid as uuidlib

from .protocol import canonical, digest, fail, iso, timestamp, token

SCHEMA = """
CREATE TABLE IF NOT EXISTS auth_config (id INTEGER PRIMARY KEY CHECK(id=1), salt TEXT NOT NULL, verifier TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS owner_tokens (token_hash TEXT PRIMARY KEY, expires_at REAL NOT NULL, created_at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (
 id TEXT PRIMARY KEY, status TEXT NOT NULL CHECK(status IN ('pairing','active','revoked')),
 pairing_code_hash TEXT UNIQUE, pairing_expires_at REAL NOT NULL, device_token_hash TEXT UNIQUE, device_name TEXT,
 expires_at REAL NOT NULL, project_session_id TEXT, project_revision INTEGER NOT NULL DEFAULT 0 CHECK(project_revision>=0),
 state TEXT NOT NULL DEFAULT '{}', capture_ready_id TEXT, capture_stop_id TEXT,
 browser_seen_at REAL, native_seen_at REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS commands (
 command_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
 payload_hash TEXT NOT NULL, envelope TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('queued','running','succeeded','failed','rejected','expired')),
 result TEXT, result_hash TEXT, created_at REAL NOT NULL, expires_at REAL NOT NULL, claimed_at REAL, completed_at REAL
);
CREATE UNIQUE INDEX IF NOT EXISTS one_running_command ON commands(session_id) WHERE status='running';
CREATE INDEX IF NOT EXISTS queued_commands ON commands(session_id,created_at) WHERE status='queued';
CREATE INDEX IF NOT EXISTS commands_cleanup ON commands(created_at);
CREATE TABLE IF NOT EXISTS planning_requests (
 command_id TEXT NOT NULL REFERENCES commands(command_id) ON DELETE CASCADE,
 operation TEXT NOT NULL, request_hash TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('running','completed')),
 response TEXT, created_at REAL NOT NULL, completed_at REAL,
 PRIMARY KEY(command_id,operation)
);
CREATE TABLE IF NOT EXISTS rate_limits (bucket TEXT PRIMARY KEY, window_start REAL NOT NULL, count INTEGER NOT NULL);
PRAGMA user_version=1;
"""


class Store:
    def __init__(self, directory, password, clock=time.time):
        path = Path(directory)
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        database = path / "relay.sqlite3"
        self.clock, self.lock = clock, threading.RLock()
        self.db = sqlite3.connect(str(database), timeout=5, isolation_level=None, check_same_thread=False)
        database.chmod(0o600)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1):
            self.db.close()
            raise RuntimeError("This relay database requires a newer backend version.")
        self.db.executescript(SCHEMA)
        self._configure_password(password)
        self.cleanup()

    @contextmanager
    def transaction(self):
        with self.lock:
            self.db.execute("BEGIN IMMEDIATE")
            try:
                yield self.db
                self.db.execute("COMMIT")
            except BaseException:
                self.db.execute("ROLLBACK")
                raise

    @staticmethod
    def _password_hash(password, salt):
        return hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1, dklen=32).hex()

    def _configure_password(self, password):
        with self.transaction() as db:
            row = db.execute("SELECT salt,verifier FROM auth_config WHERE id=1").fetchone()
            salt = row["salt"] if row else secrets.token_hex(32)
            verifier = self._password_hash(password, salt)
            if row and not hmac.compare_digest(verifier, row["verifier"]):
                # Password rotation also revokes native credentials, not just login.
                db.execute("DELETE FROM owner_tokens")
                for session in db.execute("SELECT id FROM sessions WHERE status!='revoked'").fetchall():
                    self._revoke(db, session["id"], self.clock())
            db.execute("INSERT OR REPLACE INTO auth_config(id,salt,verifier) VALUES(1,?,?)", (salt, verifier))
        self.password_salt, self.password_verifier = salt, verifier

    def rate(self, bucket, limit, seconds=60):
        with self.transaction() as db:
            now = self.clock()
            row = db.execute("SELECT * FROM rate_limits WHERE bucket=?", (bucket,)).fetchone()
            count, start = (1, now) if row is None or row["window_start"] <= now - seconds else (row["count"] + 1, row["window_start"])
            db.execute("INSERT OR REPLACE INTO rate_limits VALUES(?,?,?)", (bucket, start, count))
        if count > limit: fail(429, "rate_limited", "Too many requests; try again shortly")

    def login(self, password):
        candidate = self._password_hash(password, self.password_salt)
        if not hmac.compare_digest(candidate, self.password_verifier): fail(401, "invalid_credentials", "Incorrect owner password")
        bearer = token("mr_owner_")
        with self.transaction() as db:
            now = self.clock()
            db.execute("INSERT INTO owner_tokens VALUES(?,?,?)", (digest(bearer), now + 43200, now))
        return {"access_token": bearer, "token_type": "bearer", "expiresAt": iso(now + 43200), "user": {"id": "owner"}}

    def authenticate_owner(self, bearer):
        hashed = digest(bearer)
        with self.transaction() as db:
            row = db.execute("SELECT expires_at FROM owner_tokens WHERE token_hash=?", (hashed,)).fetchone()
            if not row or row["expires_at"] <= self.clock(): fail(401, "invalid_user_token", "Sign in again to continue")
            return {"owner": True, "token_hash": hashed, "expires_at": row["expires_at"]}

    def logout(self, actor):
        with self.transaction() as db:
            db.execute("DELETE FROM owner_tokens WHERE token_hash=?", (actor["token_hash"],))
        return {"ok": True}

    def cleanup(self):
        with self.transaction() as db:
            now = self.clock()
            count = db.execute("DELETE FROM commands WHERE created_at<?", (now - 7 * 86400,)).rowcount
            db.execute("DELETE FROM sessions WHERE expires_at<?", (now - 7 * 86400,))
            db.execute("DELETE FROM owner_tokens WHERE expires_at<=?", (now,))
            db.execute("DELETE FROM rate_limits WHERE window_start<?", (now - 86400,))
        return count

    def close(self):
        with self.lock:
            self.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            self.db.close()

    @staticmethod
    def _saved(row):
        return {"commandId": row["command_id"], "status": row["status"], "result": json.loads(row["result"]) if row["result"] else None,
                "claimedAt": iso(row["claimed_at"]) if row["claimed_at"] is not None else None,
                "completedAt": iso(row["completed_at"]) if row["completed_at"] is not None else None}

    @staticmethod
    def _terminal(db, command_id, status, message, now):
        result = canonical({"commandId": command_id, "status": status, "message": message})
        db.execute("UPDATE commands SET status=?,result=?,completed_at=? WHERE command_id=?", (status, result, now, command_id))

    def _revoke(self, db, session_id, now):
        db.execute("UPDATE sessions SET status='revoked',pairing_code_hash=NULL,device_token_hash=NULL,capture_ready_id=NULL,capture_stop_id=NULL,updated_at=? WHERE id=?", (now, session_id))
        for row in db.execute("SELECT command_id FROM commands WHERE session_id=? AND status='queued'", (session_id,)).fetchall():
            self._terminal(db, row["command_id"], "rejected", "Session revoked", now)
        # Running commands remain uncertain, never queued again.

    def relay(self, action, actor=None, session_id=None, payload=None):
        actor, payload = actor or {}, payload or {}
        browser = actor.get("owner") is True
        with self.transaction() as db:
            now = self.clock()
            if action == "pairing_create":
                if not browser: fail(403, "browser_auth_required")
                sid = str(uuidlib.uuid4())
                db.execute("INSERT INTO sessions(id,status,pairing_code_hash,pairing_expires_at,expires_at,browser_seen_at,created_at,updated_at) VALUES(?,'pairing',?,?,?,?,?,?)",
                           (sid, payload["code_hash"], now + 300, now + 43200, now, now, now))
                return {"sessionId": sid, "expiresAt": iso(now + 300)}
            if action == "pairing_claim":
                row = db.execute("SELECT * FROM sessions WHERE pairing_code_hash=?", (payload["code_hash"],)).fetchone()
                if not row or row["status"] != "pairing" or row["pairing_expires_at"] <= now or row["expires_at"] <= now:
                    fail(410, "pairing_unavailable")
                db.execute("UPDATE sessions SET status='active',device_token_hash=?,device_name=?,pairing_code_hash=NULL,native_seen_at=?,updated_at=? WHERE id=?",
                           (payload["device_hash"], payload["device_name"], now, now, row["id"]))
                return {"sessionId": row["id"], "expiresAt": iso(row["expires_at"])}
            s = db.execute("SELECT * FROM sessions WHERE id=?", (session_id,)).fetchone()
            native = bool(s and actor.get("device_hash") and s["device_token_hash"] and hmac.compare_digest(actor["device_hash"], s["device_token_hash"]))
            if not s or not (browser or native): fail(404, "session_not_found")
            if action == "revoke":
                if not browser: fail(403, "browser_auth_required")
                self._revoke(db, session_id, now)
                return {"ok": True}
            if s["status"] == "revoked" or s["expires_at"] <= now: fail(410, "session_expired_or_revoked")
            state = json.loads(s["state"])
            browser_connected = s["browser_seen_at"] is not None and s["browser_seen_at"] > now - 15
            if action == "get_state":
                return {"sessionId": session_id, "status": s["status"], "projectSessionId": s["project_session_id"], "projectRevision": s["project_revision"],
                        "state": state, "updatedAt": iso(s["updated_at"]), "nativeConnected": s["native_seen_at"] is not None and s["native_seen_at"] > now - 15,
                        "browserConnected": browser_connected, "expiresAt": iso(s["expires_at"])}
            if action in ("submit", "presence", "capture_ready", "emergency_stop") and not browser: fail(403, "browser_auth_required")
            if action in ("put_state", "poll", "result", "authorize_command", "plan_begin", "plan_finish") and not native: fail(403, "device_auth_required")
            if action == "presence":
                db.execute("UPDATE sessions SET browser_seen_at=? WHERE id=?", (now, session_id))
                return {"ok": True}
            if action == "capture_ready":
                if state.get("captureId") != payload["captureId"] or state.get("recordingPhase") != "awaiting_ready": fail(409, "stale_capture")
                if s["capture_stop_id"] == state.get("captureId"): fail(409, "capture_stopping")
                db.execute("UPDATE sessions SET capture_ready_id=?,browser_seen_at=? WHERE id=?", (payload["captureId"], now, session_id))
                return {"ok": True}
            if action == "emergency_stop":
                capture_id = state.get("captureId")
                if not capture_id or state.get("recordingPhase") in (None, "idle", "completed", "failed") or (payload.get("captureId") is not None and payload["captureId"] != capture_id):
                    fail(409, "stale_capture")
                db.execute("UPDATE sessions SET capture_stop_id=?,capture_ready_id=NULL,browser_seen_at=? WHERE id=?", (capture_id, now, session_id))
                return {"ok": True, "captureId": capture_id}
            if action == "put_state":
                if s["project_session_id"] == payload["projectSessionId"] and payload["projectRevision"] < s["project_revision"]: fail(409, "stale_revision")
                fresh = payload["state"]
                changed_capture = state.get("captureId") != fresh.get("captureId") or s["project_session_id"] != payload["projectSessionId"]
                ready = None if changed_capture or fresh.get("recordingPhase") != "awaiting_ready" else s["capture_ready_id"]
                stop = None if changed_capture or fresh.get("recordingPhase") in (None, "idle", "completed", "failed") else s["capture_stop_id"]
                db.execute("UPDATE sessions SET project_session_id=?,project_revision=?,state=?,capture_ready_id=?,capture_stop_id=?,native_seen_at=?,updated_at=? WHERE id=?",
                           (payload["projectSessionId"], payload["projectRevision"], canonical(fresh), ready, stop, now, now, session_id))
                return {"ok": True}
            if action == "get_command":
                c = db.execute("SELECT * FROM commands WHERE command_id=? AND session_id=?", (payload["commandId"], session_id)).fetchone()
                if not c: fail(404, "command_not_found")
                return self._saved(c)
            if action == "submit":
                envelope = payload["envelope"]
                payload_hash = digest(canonical(envelope))
                c = db.execute("SELECT * FROM commands WHERE command_id=?", (envelope["commandId"],)).fetchone()
                if c:
                    if c["session_id"] != session_id or c["payload_hash"] != payload_hash: fail(409, "idempotency_conflict")
                    return {**self._saved(c), "duplicate": True}
                if s["status"] != "active" or s["project_session_id"] is None: fail(409, "device_not_ready")
                if s["project_session_id"] != envelope["projectSessionId"] or s["project_revision"] != envelope["expectedProjectRevision"]: fail(409, "stale_project")
                expiry = timestamp(envelope["expiresAt"])
                if expiry <= now: fail(410, "command_expired")
                if db.execute("SELECT count(*) FROM commands WHERE session_id=? AND status IN ('queued','running')", (session_id,)).fetchone()[0] >= 20: fail(429, "queue_full")
                db.execute("INSERT INTO commands(command_id,session_id,payload_hash,envelope,status,created_at,expires_at) VALUES(?,?,?,?,'queued',?,?)",
                           (envelope["commandId"], session_id, payload_hash, canonical(envelope), now, expiry))
                db.execute("UPDATE sessions SET browser_seen_at=? WHERE id=?", (now, session_id))
                return {"commandId": envelope["commandId"], "status": "queued", "duplicate": False}
            if action == "poll":
                db.execute("UPDATE sessions SET native_seen_at=? WHERE id=?", (now, session_id))
                queued = db.execute("SELECT * FROM commands WHERE session_id=? AND status='queued' ORDER BY created_at,command_id", (session_id,)).fetchall()
                for row in queued:
                    envelope = json.loads(row["envelope"])
                    if row["expires_at"] <= now:
                        self._terminal(db, row["command_id"], "expired", "Command expired before execution", now)
                    elif envelope["projectSessionId"] != s["project_session_id"] or envelope["expectedProjectRevision"] != s["project_revision"]:
                        self._terminal(db, row["command_id"], "rejected", "Project or revision changed before execution", now)
                command = None
                if browser_connected and not db.execute("SELECT 1 FROM commands WHERE session_id=? AND status='running'", (session_id,)).fetchone():
                    next_row = db.execute("SELECT * FROM commands WHERE session_id=? AND status='queued' ORDER BY created_at,command_id LIMIT 1", (session_id,)).fetchone()
                    if next_row:
                        db.execute("UPDATE commands SET status='running',claimed_at=? WHERE command_id=?", (now, next_row["command_id"]))
                        command = json.loads(next_row["envelope"])
                return {"command": command, "captureReadyId": s["capture_ready_id"], "stopRequested": s["capture_stop_id"] is not None,
                        "cancelCaptureId": s["capture_stop_id"], "browserConnected": browser_connected}
            if action in ("result", "authorize_command", "plan_begin", "plan_finish"):
                c = db.execute("SELECT * FROM commands WHERE command_id=? AND session_id=?", (payload["commandId"], session_id)).fetchone()
                if not c: fail(404, "command_not_found")
                if action in ("authorize_command", "plan_begin", "plan_finish"):
                    if c["status"] != "running" or c["expires_at"] <= now: fail(409, "command_not_running")
                    envelope = json.loads(c["envelope"])
                    if envelope["projectSessionId"] != s["project_session_id"] or envelope["expectedProjectRevision"] != s["project_revision"]: fail(409, "stale_project")
                    if action == "authorize_command": return {"ok": True}
                    previous = db.execute("SELECT * FROM planning_requests WHERE command_id=? AND operation=?", (c["command_id"], payload["operation"])).fetchone()
                    if previous and previous["request_hash"] != payload["requestHash"]: fail(409, "planning_conflict", "This command already has a different planning request")
                    if action == "plan_begin":
                        if previous:
                            if previous["status"] == "running": fail(409, "planning_in_progress", "This command is already being planned; it will not be planned twice")
                            return {"cached": True, "result": json.loads(previous["response"])}
                        db.execute("INSERT INTO planning_requests(command_id,operation,request_hash,status,created_at) VALUES(?,?,?,'running',?)", (c["command_id"], payload["operation"], payload["requestHash"], now))
                        return {"cached": False}
                    if not previous or previous["status"] != "running": fail(409, "planning_conflict")
                    db.execute("UPDATE planning_requests SET status='completed',response=?,completed_at=? WHERE command_id=? AND operation=?", (canonical(payload["result"]), now, c["command_id"], payload["operation"]))
                    return {"ok": True}
                result_hash = digest(canonical(payload["result"]))
                if c["status"] != "running":
                    if c["result_hash"] == result_hash: return {"ok": True, "duplicate": True}
                    fail(409, "result_conflict")
                result = payload["result"]
                if result["status"] not in ("succeeded", "failed", "rejected"): fail(400, "invalid_result")
                db.execute("UPDATE commands SET status=?,result=?,result_hash=?,completed_at=? WHERE command_id=?", (result["status"], canonical(result), result_hash, now, c["command_id"]))
                db.execute("UPDATE sessions SET native_seen_at=? WHERE id=?", (now, session_id))
                return {"ok": True, "duplicate": False}
            fail(400, "unknown_operation")
