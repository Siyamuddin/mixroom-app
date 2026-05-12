from __future__ import annotations

import logging
from typing import Any, Dict

from common import config
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.models import normalize_plan_code, status_has_active_access
from common.native_auth import AppUserAuthError, verify_current_password
from common.rate_limits import RequestRateLimiter, client_ip_from_event
from common.repository import BillingRepository, UsernameClaimConflictError
from common.producer_capture_whitelist_repository import (
    ProducerCaptureWhitelistRepository,
)
from common.social_auth import SocialAuthError, verify_social_reauthentication
from common.stibee import StibeeConfigError, StibeeSyncError, sync_user_profile
from common.users import (
    apply_user_profile_patch,
    build_user_profile_from_claims,
    normalize_username,
    user_profile_needs_claim_sync,
    validate_username,
)

repo = BillingRepository()
rate_limiter = RequestRateLimiter()
producer_capture_whitelist_repo = ProducerCaptureWhitelistRepository()
logger = logging.getLogger(__name__)


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

    profile = _resolve_user_profile_for_claims(claims)
    return json_response(200, profile)


def _resolve_user_profile_for_claims(claims: Dict[str, Any]) -> Dict[str, Any]:
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        raise ValueError("Missing user identifier.")
    existing = repo.get_user_profile(user_id)
    if existing and not user_profile_needs_claim_sync(claims, existing=existing):
        return existing
    else:
        profile = build_user_profile_from_claims(claims, existing=existing)
        repo.upsert_user_profile(
            profile,
            previous_username_lc=str((existing or {}).get("username_lc") or "").strip().lower()
            or None,
        )
        return profile


def _get_producer_capture_ui_access(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not config.USERS_TABLE:
        return json_response(503, {"error": "Users table is not configured."})

    profile = _resolve_user_profile_for_claims(claims)
    username = normalize_username(str(profile.get("username") or ""))
    settings = producer_capture_whitelist_repo.get_whitelist_settings()
    usernames = settings.get("usernames") if isinstance(settings, dict) else []
    allowlist = {
        normalize_username(item)
        for item in usernames
        if normalize_username(item)
    }
    return json_response(
        200,
        {
            "enabled": bool(username and username in allowlist),
            "username": username,
            "source": str(settings.get("source") or "default"),
        },
    )


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
        try:
            sync_user_profile(
                previous_profile=base_profile,
                next_profile=profile,
                locale_code=body.get("locale_code"),
            )
        except (StibeeConfigError, StibeeSyncError) as exc:
            logger.warning(
                "Stibee profile sync failed; persisting local profile update anyway.",
                extra={
                    "user_id": user_id,
                    "has_newsletter_opt_in_patch": "newsletter_opt_in" in body,
                    "has_locale_patch": "locale_code" in body,
                    "error": str(exc),
                },
            )
        repo.upsert_user_profile(
            profile,
            previous_username_lc=previous_username_lc,
        )
        return json_response(200, profile)
    except ValueError as exc:
        return json_response(400, {"error": str(exc)})
    except UsernameClaimConflictError as exc:
        return json_response(409, {"error": str(exc)})


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
    plan_code = normalize_plan_code(
        entitlement.get("plan_code") or entitlement.get("tier") or "free"
    )
    status = str(entitlement.get("status") or "active").strip()
    if plan_code != "free" and status_has_active_access(status):
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
    if method == "GET" and path.endswith("/v1/users/me/producer-capture-ui-access"):
        return _get_producer_capture_ui_access(event)
    if method == "GET" and path.endswith("/v1/users/me"):
        return _get_me(event)
    if method == "PATCH" and path.endswith("/v1/users/me"):
        return _patch_me(event)
    if method == "DELETE" and path.endswith("/v1/users/me"):
        return _delete_me(event)

    return json_response(404, {"error": "Not found"})
