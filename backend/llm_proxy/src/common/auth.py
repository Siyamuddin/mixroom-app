from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from datetime import datetime, timezone
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local test fallback
    boto3 = None

from . import config

_secrets = boto3.client("secretsmanager") if boto3 is not None else None
_ddb = boto3.resource("dynamodb") if boto3 is not None else None
_secret_cache: str | None = None
_auth_accounts = (
    _ddb.Table(config.AUTH_ACCOUNTS_TABLE)
    if _ddb is not None and config.AUTH_ACCOUNTS_TABLE
    else None
)
_auth_sessions = (
    _ddb.Table(config.AUTH_SESSIONS_TABLE)
    if _ddb is not None and config.AUTH_SESSIONS_TABLE
    else None
)


def unauthorized(message: str = "Unauthorized") -> Dict[str, Any]:
    return {
        "statusCode": 401,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }


def extract_user_id_from_event(event: Dict[str, Any]) -> str:
    claims = extract_claims_from_event(event)
    return str(claims.get("sub") or "").strip()


def extract_claims_from_event(event: Dict[str, Any]) -> Dict[str, Any]:
    request_context = event.get("requestContext") or {}
    authorizer = request_context.get("authorizer") or {}

    jwt_data = authorizer.get("jwt") or {}
    claims = jwt_data.get("claims") or {}
    if isinstance(claims, dict) and _claims_match_native_source(claims):
        sub = str(claims.get("sub") or "").strip()
        if sub:
            return dict(claims)

    headers = event.get("headers") or {}
    auth_header = headers.get("authorization") or headers.get("Authorization") or ""
    token = auth_header.replace("Bearer", "").strip()
    if not token or not config.APP_AUTH_SECRET_ARN:
        return {}

    try:
        payload = _verify_native_token(token)
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _claims_match_native_source(claims: Dict[str, Any]) -> bool:
    issuer = str(claims.get("iss") or "").strip()
    subject = str(claims.get("sub") or "").strip()
    session_id = str(claims.get("sid") or "").strip()
    token_use = str(claims.get("token_use") or "").strip()
    audience = str(claims.get("aud") or "").strip()
    return (
        issuer == config.APP_AUTH_ISSUER
        and audience == config.APP_AUTH_AUDIENCE
        and bool(subject)
        and bool(session_id)
        and token_use in ("access", "id")
    )


def json_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body),
    }


def _verify_native_token(token: str) -> Dict[str, Any]:
    parts = str(token or "").strip().split(".")
    if len(parts) != 3:
        raise ValueError("Token format is invalid.")
    header_segment, payload_segment, signature_segment = parts
    signing_input = f"{header_segment}.{payload_segment}".encode("ascii")
    expected_signature = _sign(signing_input)
    if not hmac.compare_digest(signature_segment, expected_signature):
        raise ValueError("Token signature is invalid.")
    payload = _decode_segment(payload_segment)
    if not isinstance(payload, dict):
        raise ValueError("Token payload is invalid.")
    if str(payload.get("iss") or "").strip() != config.APP_AUTH_ISSUER:
        raise ValueError("Token issuer is invalid.")
    if str(payload.get("aud") or "").strip() != config.APP_AUTH_AUDIENCE:
        raise ValueError("Token audience is invalid.")
    if int(payload.get("exp") or 0) <= int(time.time()):
        raise ValueError("Token has expired.")
    token_use = str(payload.get("token_use") or "").strip()
    if token_use not in ("access", "id"):
        raise ValueError("Token use is invalid.")
    user_id = str(payload.get("sub") or "").strip()
    session_id = str(payload.get("sid") or "").strip()
    if not user_id or not session_id:
        raise ValueError("Token session is invalid.")
    if _auth_sessions is None or _auth_accounts is None:
        raise ValueError("Auth tables are unavailable.")

    session = _auth_sessions.get_item(Key={"session_id": session_id}).get("Item")
    if not isinstance(session, dict):
        raise ValueError("Session no longer exists.")
    if _is_expired(session.get("expires_at")):
        _auth_sessions.delete_item(Key={"session_id": session_id})
        raise ValueError("Session has expired.")
    if str(session.get("user_id") or "").strip() != user_id:
        raise ValueError("Session user is invalid.")
    account = _auth_accounts.get_item(Key={"user_id": user_id}).get("Item")
    if not isinstance(account, dict):
        _auth_sessions.delete_item(Key={"session_id": session_id})
        raise ValueError("Account no longer exists.")
    return payload


def _decode_segment(segment: str) -> Any:
    padded = segment + "=" * (-len(segment) % 4)
    decoded = base64.urlsafe_b64decode(padded.encode("ascii"))
    return json.loads(decoded.decode("utf-8"))


def _sign(payload: bytes) -> str:
    secret = _load_secret().encode("utf-8")
    digest = hmac.new(secret, payload, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def _load_secret() -> str:
    global _secret_cache
    if _secret_cache is not None:
        return _secret_cache
    if _secrets is None:
        raise ValueError("Secrets client is unavailable.")
    response = _secrets.get_secret_value(SecretId=config.APP_AUTH_SECRET_ARN)
    raw = response.get("SecretString") or ""
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw
    if isinstance(parsed, dict):
        for key in ("secret", "jwt_secret", "app_auth_secret", "key"):
            value = str(parsed.get(key) or "").strip()
            if value:
                _secret_cache = value
                return value
        raise ValueError("App auth secret JSON is invalid.")
    value = str(parsed).strip()
    if not value:
        raise ValueError("App auth secret is empty.")
    _secret_cache = value
    return value


def _is_expired(value: Any) -> bool:
    raw = str(value or "").strip()
    if not raw:
        return True
    try:
        expires_at = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return True
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    else:
        expires_at = expires_at.astimezone(timezone.utc)
    return expires_at <= datetime.now(timezone.utc)
