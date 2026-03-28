from __future__ import annotations

import secrets

from typing import Any, Dict

from common import config
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.models import normalize_tier, status_has_active_access
from common.native_auth import AppUserAuthError, verify_current_password
from common.rate_limits import RequestRateLimiter, client_ip_from_event
from common.repository import BillingRepository, UsernameClaimConflictError
from common.social_auth import SocialAuthError, verify_social_reauthentication
from common.users import (
    apply_user_profile_patch,
    build_user_profile_from_claims,
    default_onboarding_state,
    normalize_username,
    user_profile_needs_claim_sync,
    validate_username,
)

repo = BillingRepository()
rate_limiter = RequestRateLimiter()
_AUTO_USERNAME_PREFIX = "mixroom-user"
_AUTO_USERNAME_MAX_ATTEMPTS = 10


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _profile_needs_generated_username(profile: Dict[str, Any]) -> bool:
    return bool(
        str(profile.get("accepted_terms_version") or "").strip()
        and str(profile.get("accepted_privacy_version") or "").strip()
        and str(profile.get("birthdate") or "").strip()
        and not str(profile.get("username") or "").strip()
    )


def _generate_default_username() -> str:
    return f"{_AUTO_USERNAME_PREFIX}{secrets.randbelow(1_000_000_000):09d}"


def _assign_generated_username(profile: Dict[str, Any]) -> Dict[str, Any]:
    updated = dict(profile)
    generated = _generate_default_username()
    updated["username"] = generated
    updated["username_lc"] = generated
    updated["onboarding_state"] = default_onboarding_state(updated)
    return updated


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
    previous_username_lc = (
        str((existing or {}).get("username_lc") or "").strip().lower() or None
    )

    try:
        profile = apply_user_profile_patch(base_profile, body)
        if not _profile_needs_generated_username(profile):
            repo.upsert_user_profile(
                profile,
                previous_username_lc=previous_username_lc,
            )
            return json_response(200, profile)

        last_conflict: UsernameClaimConflictError | None = None
        for _ in range(_AUTO_USERNAME_MAX_ATTEMPTS):
            generated_profile = _assign_generated_username(profile)
            try:
                repo.upsert_user_profile(
                    generated_profile,
                    previous_username_lc=previous_username_lc,
                )
                return json_response(200, generated_profile)
            except UsernameClaimConflictError as exc:
                last_conflict = exc
                continue
        if last_conflict is not None:
            raise last_conflict
    except ValueError as exc:
        return json_response(400, {"error": str(exc)})
    except UsernameClaimConflictError as exc:
        return json_response(409, {"error": str(exc)})
    return json_response(
        503,
        {"error": "We couldn't reserve a default username. Please try again."},
    )


def _delete_me(event: Dict[str, Any]) -> Dict[str, Any]:
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

    confirmation_text = str(
        body.get("confirmation_text") or body.get("confirmationText") or ""
    ).strip()
    if confirmation_text.upper() != "DELETE":
        return json_response(
            400,
            {
                "error": "Type DELETE to confirm account deletion.",
                "code": "DELETE_CONFIRMATION_REQUIRED",
            },
        )

    existing = repo.get_user_profile(user_id) or {}
    account = repo.get_auth_account(user_id) or {}
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

    provider = (
        str(account.get("auth_provider") or existing.get("auth_provider") or "").strip().lower()
        or "email"
    )
    if provider == "email":
        current_password = str(
            body.get("current_password") or body.get("currentPassword") or ""
        )
        if not current_password:
            return json_response(
                400,
                {
                    "error": "Enter your current password to delete this account.",
                    "code": "DELETE_PASSWORD_REQUIRED",
                },
            )
        try:
            verify_current_password(
                repo,
                user_id=user_id,
                current_password=current_password,
            )
        except AppUserAuthError as exc:
            return json_response(
                exc.status_code,
                {
                    "error": exc.message,
                    "code": exc.code,
                    **({"details": exc.details} if exc.details else {}),
                },
            )
    else:
        social_reauth = body.get("social_reauth") or body.get("socialReauth") or {}
        if not isinstance(social_reauth, dict) or not social_reauth:
            provider_label = {
                "google": "Google",
                "apple": "Apple",
                "kakao": "KakaoTalk",
            }.get(provider, "your social provider")
            return json_response(
                400,
                {
                    "error": f"Re-authenticate with {provider_label} to delete this account.",
                    "code": "SOCIAL_REAUTH_REQUIRED",
                    "details": {"provider": provider},
                },
            )
        try:
            verify_social_reauthentication(
                repo,
                user_id=user_id,
                payload=social_reauth,
            )
        except SocialAuthError as exc:
            return json_response(
                exc.status_code,
                {
                    "error": exc.message,
                    "code": exc.code,
                    **({"details": exc.details} if exc.details else {}),
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
