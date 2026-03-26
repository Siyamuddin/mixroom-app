from __future__ import annotations

import json
from decimal import Decimal
from typing import Any, Dict, Iterable

from .app_auth_tokens import AppAuthTokenError, verify_token
from . import config
from .cognito_legacy_auth import verify_cognito_token
from .repository import BillingRepository

_repo = BillingRepository()


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"Object of type {value.__class__.__name__} is not JSON serializable")


def unauthorized(message: str = "Unauthorized") -> Dict[str, Any]:
    return {
        "statusCode": 401,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Signature",
            "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
        },
        "body": json.dumps({"error": message}, default=_json_default),
    }


def extract_claims_from_event(
    event: Dict[str, Any],
    *,
    audiences: Iterable[str] | None = None,
    user_pool_ids: Iterable[str] | None = None,
    allow_native: bool = True,
    allow_cognito: bool = False,
) -> Dict[str, Any]:
    request_context = event.get("requestContext") or {}
    authorizer = request_context.get("authorizer") or {}

    jwt_data = authorizer.get("jwt") or {}
    claims = jwt_data.get("claims") or {}
    if isinstance(claims, dict) and claims:
        if _claims_match_allowed_source(
            claims,
            audiences=audiences,
            user_pool_ids=user_pool_ids,
            allow_native=allow_native,
            allow_cognito=allow_cognito,
        ):
            return dict(claims)

    headers = event.get("headers") or {}
    auth_header = headers.get("authorization") or headers.get("Authorization") or ""
    token = auth_header.replace("Bearer", "").strip()
    if not token:
        return {}

    if allow_native and config.APP_AUTH_SECRET_ARN:
        try:
            payload = _verify_native_session_claims(token)
            if isinstance(payload, dict) and str(payload.get("sub") or "").strip():
                return payload
        except AppAuthTokenError:
            pass

    if not allow_cognito:
        return {}

    accepted_audiences = [
        value.strip()
        for value in (audiences or [config.COGNITO_APP_CLIENT_ID])
        if str(value or "").strip()
    ]
    accepted_user_pool_ids = [
        value.strip()
        for value in (user_pool_ids or [config.COGNITO_USER_POOL_ID])
        if str(value or "").strip()
    ]
    if not config.COGNITO_REGION or not accepted_user_pool_ids or not accepted_audiences:
        return {}

    try:
        payload = verify_cognito_token(
            token,
            audiences=accepted_audiences,
            user_pool_ids=accepted_user_pool_ids,
        )
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _claims_match_allowed_source(
    claims: Dict[str, Any],
    *,
    audiences: Iterable[str] | None,
    user_pool_ids: Iterable[str] | None,
    allow_native: bool,
    allow_cognito: bool,
) -> bool:
    issuer = str(claims.get("iss") or "").strip()
    subject = str(claims.get("sub") or "").strip()
    token_use = str(claims.get("token_use") or "").strip()
    if not issuer or not subject:
        return False

    if allow_native and issuer == config.APP_AUTH_ISSUER:
        session_id = str(claims.get("sid") or "").strip()
        return bool(session_id and token_use == "access")

    if not allow_cognito:
        return False

    accepted_audiences = {
        str(value or "").strip()
        for value in (audiences or [config.COGNITO_APP_CLIENT_ID])
        if str(value or "").strip()
    }
    accepted_user_pool_ids = {
        str(value or "").strip()
        for value in (user_pool_ids or [config.COGNITO_USER_POOL_ID])
        if str(value or "").strip()
    }
    if not config.COGNITO_REGION or not accepted_user_pool_ids or not accepted_audiences:
        return False

    expected_prefix = (
        f"https://cognito-idp.{config.COGNITO_REGION}.amazonaws.com/"
    )
    if not issuer.startswith(expected_prefix):
        return False

    pool_id = issuer.removeprefix(expected_prefix).strip("/")
    if pool_id not in accepted_user_pool_ids:
        return False

    audience = str(claims.get("aud") or claims.get("client_id") or "").strip()
    return bool(audience and audience in accepted_audiences)


def extract_user_id_from_event(event: Dict[str, Any]) -> str:
    claims = extract_claims_from_event(event)
    return str(claims.get("sub") or "").strip()


def json_response(
    status_code: int,
    body: Dict[str, Any],
    *,
    headers: Dict[str, str] | None = None,
) -> Dict[str, Any]:
    response_headers = {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Signature",
        "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
    }
    if headers:
        response_headers.update(headers)
    return {
        "statusCode": status_code,
        "headers": response_headers,
        "body": json.dumps(body, default=_json_default),
    }


def _verify_native_session_claims(token: str) -> Dict[str, Any]:
    payload = verify_token(token)
    if not isinstance(payload, dict):
        raise AppAuthTokenError("Token payload is invalid.")
    token_use = str(payload.get("token_use") or "").strip()
    if token_use != "access":
        raise AppAuthTokenError("Token use is invalid.")
    user_id = str(payload.get("sub") or "").strip()
    session_id = str(payload.get("sid") or "").strip()
    if not user_id or not session_id:
        raise AppAuthTokenError("Token session is invalid.")

    session = _repo.get_auth_session(session_id)
    if not session:
        raise AppAuthTokenError("Session no longer exists.")
    if str(session.get("user_id") or "").strip() != user_id:
        raise AppAuthTokenError("Session user is invalid.")
    if not _repo.get_auth_account(user_id):
        _repo.delete_auth_session(session_id)
        raise AppAuthTokenError("Account no longer exists.")
    return payload
