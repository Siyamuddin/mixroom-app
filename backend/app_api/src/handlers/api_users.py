from __future__ import annotations

from typing import Any, Dict

from common import config
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.models import normalize_tier, status_has_active_access
from common.rate_limits import RequestRateLimiter, client_ip_from_event
from common.repository import BillingRepository, UsernameClaimConflictError
from common.users import (
    apply_user_profile_patch,
    build_user_profile_from_claims,
    normalize_username,
    user_profile_needs_claim_sync,
    validate_username,
)

repo = BillingRepository()
rate_limiter = RequestRateLimiter()


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _get_username_availability(event: Dict[str, Any]) -> Dict[str, Any]:
    if not config.USERS_TABLE:
        return json_response(503, {"error": "Users table is not configured."})

    client_ip = client_ip_from_event(event)
    decision = rate_limiter.enforce(
        scope_key=f"username_availability:ip:{client_ip}",
        limit=600,
        window_seconds=300,
        block_seconds=300,
    )
    if client_ip and not decision.allowed:
        retry_after = max(1, decision.retry_after_seconds)
        return json_response(
            429,
            {
                "error": "Too many attempts. Please try again later.",
                "code": "RATE_LIMITED",
                "retry_after_seconds": retry_after,
            },
            headers={"Retry-After": str(retry_after)},
        )

    query = event.get("queryStringParameters") or {}
    raw_username = str((query.get("username") if isinstance(query, dict) else "") or "").strip()
    username = normalize_username(raw_username)
    username_error = validate_username(username)
    if username_error:
        return json_response(
            200,
            {
                "available": False,
                "normalized_username": username,
                "reason": username_error,
            },
        )

    existing_claim = repo.get_username_claim(username or "")
    return json_response(
        200,
        {
            "available": existing_claim is None,
            "normalized_username": username,
            "reason": None if existing_claim is None else "That username is already taken.",
        },
    )


def _get_me(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not config.USERS_TABLE:
        return json_response(503, {"error": "Users table is not configured."})

    existing = repo.get_user_profile(user_id)
    if existing and not user_profile_needs_claim_sync(claims, existing=existing):
        profile = existing
    else:
        profile = build_user_profile_from_claims(claims, existing=existing)
        repo.upsert_user_profile(
            profile,
            previous_username_lc=str((existing or {}).get("username_lc") or "").strip().lower()
            or None,
        )
    return json_response(200, profile)


def _patch_me(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not config.USERS_TABLE:
        return json_response(503, {"error": "Users table is not configured."})

    try:
        body = parse_json_body(event)
    except RequestBodyError as exc:
        return json_response(exc.status_code, {"error": exc.message})

    existing = repo.get_user_profile(user_id)
    base_profile = build_user_profile_from_claims(claims, existing=existing)

    try:
        profile = apply_user_profile_patch(base_profile, body)
        repo.upsert_user_profile(
            profile,
            previous_username_lc=str((existing or {}).get("username_lc") or "").strip().lower()
            or None,
        )
    except ValueError as exc:
        return json_response(400, {"error": str(exc)})
    except UsernameClaimConflictError as exc:
        return json_response(409, {"error": str(exc)})

    return json_response(200, profile)


def _delete_me(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not config.USERS_TABLE:
        return json_response(503, {"error": "Users table is not configured."})

    existing = repo.get_user_profile(user_id) or {}
    entitlement = repo.get_entitlement(user_id) or {}
    tier = normalize_tier(str(entitlement.get("tier") or "free"))
    status = str(entitlement.get("status") or "active").strip()
    if tier != "free" and status_has_active_access(status):
        return json_response(
            409,
            {
                "error": (
                    "Cancel your active subscription first in the App Store, "
                    "Google Play, or web billing portal before deleting your account."
                )
            },
        )

    repo.delete_user_account_data(
        user_id,
        username_lc=str(existing.get("username_lc") or "").strip().lower()
        or None,
    )
    return json_response(200, {"deleted": True})


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    method = _method(event)

    if method == "GET" and path.endswith("/v1/users/username-availability"):
        return _get_username_availability(event)
    if method == "GET" and path.endswith("/v1/users/me"):
        return _get_me(event)
    if method == "PATCH" and path.endswith("/v1/users/me"):
        return _patch_me(event)
    if method == "DELETE" and path.endswith("/v1/users/me"):
        return _delete_me(event)

    return json_response(404, {"error": "Not found"})
