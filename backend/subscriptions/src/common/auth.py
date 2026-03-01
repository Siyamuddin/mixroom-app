from __future__ import annotations

import base64
import json
from typing import Any, Dict


def unauthorized(message: str = "Unauthorized") -> Dict[str, Any]:
    return {
        "statusCode": 401,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }


def extract_user_id_from_event(event: Dict[str, Any]) -> str:
    # Preferred source: API Gateway JWT authorizer claims
    request_context = event.get("requestContext") or {}
    authorizer = request_context.get("authorizer") or {}

    jwt_data = authorizer.get("jwt") or {}
    claims = jwt_data.get("claims") or {}
    if isinstance(claims, dict):
        sub = (claims.get("sub") or "").strip()
        if sub:
            return sub

    # Fallback: decode bearer token payload without signature verification.
    # This is only acceptable for internal staging scaffolding.
    headers = event.get("headers") or {}
    auth_header = headers.get("authorization") or headers.get("Authorization") or ""
    token = auth_header.replace("Bearer", "").strip()
    if not token:
        return ""

    parts = token.split(".")
    if len(parts) < 2:
        return ""

    payload_b64 = parts[1]
    padding = '=' * ((4 - len(payload_b64) % 4) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload_b64 + padding)
        payload = json.loads(decoded.decode("utf-8"))
        if isinstance(payload, dict):
            return str(payload.get("sub") or "").strip()
    except Exception:
        return ""

    return ""


def json_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body),
    }
