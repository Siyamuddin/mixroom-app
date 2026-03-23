from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
import uuid
from typing import Any, Dict

from . import config
from .secrets import load_app_auth_secret


class AppAuthTokenError(ValueError):
    pass


def mint_token(
    claims: Dict[str, Any],
    *,
    ttl_seconds: int | None = None,
    token_use: str = "access",
) -> str:
    now = int(time.time())
    payload = {
        "iss": config.APP_AUTH_ISSUER,
        "aud": config.APP_AUTH_AUDIENCE,
        "iat": now,
        "exp": now + max(60, int(ttl_seconds or config.APP_AUTH_ACCESS_TOKEN_TTL_SECONDS)),
        "jti": str(uuid.uuid4()),
        "token_use": token_use,
        **claims,
    }
    header = {
        "alg": "HS256",
        "typ": "JWT",
    }
    header_segment = _base64url_json(header)
    payload_segment = _base64url_json(payload)
    signing_input = f"{header_segment}.{payload_segment}"
    signature = _sign(signing_input.encode("ascii"))
    return f"{signing_input}.{signature}"


def verify_token(
    token: str,
    *,
    expected_audience: str | None = None,
    expected_issuer: str | None = None,
) -> Dict[str, Any]:
    safe_token = str(token or "").strip()
    if not safe_token:
        raise AppAuthTokenError("Missing token.")

    parts = safe_token.split(".")
    if len(parts) != 3:
        raise AppAuthTokenError("Token format is invalid.")

    header_segment, payload_segment, signature_segment = parts
    signing_input = f"{header_segment}.{payload_segment}".encode("ascii")
    expected_signature = _sign(signing_input)
    if not hmac.compare_digest(signature_segment, expected_signature):
        raise AppAuthTokenError("Token signature is invalid.")

    payload = _decode_segment(payload_segment)
    if not isinstance(payload, dict):
        raise AppAuthTokenError("Token payload is invalid.")

    issuer = str(payload.get("iss") or "").strip()
    audience = str(payload.get("aud") or "").strip()
    if (expected_issuer or config.APP_AUTH_ISSUER) != issuer:
        raise AppAuthTokenError("Token issuer is invalid.")
    if (expected_audience or config.APP_AUTH_AUDIENCE) != audience:
        raise AppAuthTokenError("Token audience is invalid.")

    now = int(time.time())
    try:
        exp = int(payload.get("exp") or 0)
    except (TypeError, ValueError) as exc:
        raise AppAuthTokenError("Token expiration is invalid.") from exc
    if exp <= now:
        raise AppAuthTokenError("Token has expired.")

    return payload


def new_refresh_token() -> tuple[str, str]:
    session_id = str(uuid.uuid4())
    raw_secret = secrets.token_urlsafe(32)
    token = f"rt_{session_id}_{raw_secret}"
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    return token, token_hash


def parse_refresh_token(refresh_token: str) -> tuple[str, str]:
    safe = str(refresh_token or "").strip()
    if not safe.startswith("rt_"):
        raise AppAuthTokenError("Refresh token format is invalid.")
    first_sep = safe.find("_", 3)
    if first_sep <= 3:
        raise AppAuthTokenError("Refresh token format is invalid.")
    session_id = safe[3:first_sep]
    if not session_id:
        raise AppAuthTokenError("Refresh token session is missing.")
    token_hash = hashlib.sha256(safe.encode("utf-8")).hexdigest()
    return session_id, token_hash


def _base64url_json(payload: Dict[str, Any]) -> str:
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")
    return base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("=")


def _decode_segment(segment: str) -> Any:
    padded = segment + "=" * (-len(segment) % 4)
    decoded = base64.urlsafe_b64decode(padded.encode("ascii"))
    return json.loads(decoded.decode("utf-8"))


def _sign(payload: bytes) -> str:
    secret = load_app_auth_secret().encode("utf-8")
    digest = hmac.new(secret, payload, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
