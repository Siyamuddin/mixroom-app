from __future__ import annotations

import hashlib
import time
from typing import Any, Dict

from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception
from common.native_auth import (
    AppUserAuthError,
    change_password,
    confirm_email_account,
    confirm_password_reset,
    refresh_session,
    register_email_account,
    request_password_reset,
    resend_email_verification_code,
    sign_out_session,
)
from common.password_auth import PasswordAuthError, complete_password_sign_in
from common.rate_limits import RequestRateLimiter, client_ip_from_event
from common.social_auth import SocialAuthError, complete_social_sign_in
from common.repository import BillingRepository

repo = BillingRepository()
rate_limiter = RequestRateLimiter()

_RETRY_AFTER_HEADERS = "Retry-After"
_PUBLIC_RATE_LIMIT_RULES = {
    "sign_up": (
        ("ip", 60, 600, 900),
        ("email", 5, 3600, 3600),
    ),
    "confirm_sign_up": (
        ("ip", 60, 900, 900),
        ("email", 8, 1800, 1800),
    ),
    "resend_sign_up_code": (
        ("ip", 30, 900, 900),
        ("email", 1, 60, 60),
        ("email", 4, 3600, 3600),
    ),
    "social_sign_in": (
        ("ip", 120, 300, 600),
    ),
    "password_sign_in": (
        ("ip", 120, 900, 900),
        ("identifier", 10, 900, 900),
    ),
    "request_password_reset": (
        ("ip", 30, 900, 900),
        ("email", 1, 60, 60),
        ("email", 4, 3600, 3600),
    ),
    "confirm_password_reset": (
        ("ip", 60, 900, 900),
        ("email", 8, 1800, 1800),
    ),
    "refresh": (
        ("ip", 600, 300, 300),
        ("refresh_token", 40, 300, 300),
    ),
    "resend_email_verification": (
        ("user", 1, 60, 60),
        ("user", 6, 3600, 3600),
    ),
}


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _rate_limited_response(
    *,
    action_name: str,
    retry_after_seconds: int,
) -> Dict[str, Any]:
    retry_after = max(1, int(retry_after_seconds or 1))
    return json_response(
        429,
        {
            "error": "Too many attempts. Please try again later.",
            "code": "RATE_LIMITED",
            "action": action_name,
            "retry_after_seconds": retry_after,
        },
        headers={_RETRY_AFTER_HEADERS: str(retry_after)},
    )


def _parse_body(
    *,
    event: Dict[str, Any],
    allow_empty: bool = False,
) -> Dict[str, Any]:
    try:
        return parse_json_body(event)
    except RequestBodyError:
        if allow_empty and not str(event.get("body") or "").strip():
            return {}
        raise


def _body_error_response(exc: RequestBodyError) -> Dict[str, Any]:
    return json_response(exc.status_code, {"error": exc.message})


def _identifier_scope(action_name: str, body: Dict[str, Any], claims: Dict[str, Any]) -> Dict[str, str]:
    scopes: Dict[str, str] = {}
    if action_name == "sign_up":
        email = str(body.get("email") or "").strip().lower()
        if email:
            scopes["email"] = email
    elif action_name == "confirm_sign_up":
        email = str(body.get("email") or "").strip().lower()
        if email:
            scopes["email"] = email
    elif action_name == "resend_sign_up_code":
        email = str(body.get("email") or "").strip().lower()
        if email:
            scopes["email"] = email
    elif action_name == "password_sign_in":
        identifier = str(body.get("identifier") or "").strip().lower()
        if identifier:
            scopes["identifier"] = identifier
    elif action_name == "request_password_reset":
        email = str(body.get("email") or "").strip().lower()
        if email:
            scopes["email"] = email
    elif action_name == "confirm_password_reset":
        email = str(body.get("email") or "").strip().lower()
        if email:
            scopes["email"] = email
    elif action_name == "refresh":
        refresh_token = str(body.get("refresh_token") or body.get("refreshToken") or "").strip()
        if refresh_token:
            scopes["refresh_token"] = hashlib.sha256(
                refresh_token.encode("utf-8")
            ).hexdigest()
    elif action_name == "resend_email_verification":
        user_id = str(claims.get("sub") or "").strip()
        if user_id:
            scopes["user"] = user_id
    return scopes


def _enforce_rate_limit(
    *,
    event: Dict[str, Any],
    action_name: str,
    body: Dict[str, Any],
    claims: Dict[str, Any] | None = None,
) -> Dict[str, Any] | None:
    rules = _PUBLIC_RATE_LIMIT_RULES.get(action_name) or ()
    if not rules:
        return None
    scope_values = _identifier_scope(action_name, body, claims or {})
    client_ip = client_ip_from_event(event)

    retry_after_seconds = 0
    for dimension, limit, window_seconds, block_seconds in rules:
        if dimension == "ip":
            scope_value = client_ip
        else:
            scope_value = scope_values.get(dimension, "")
        normalized_value = str(scope_value or "").strip()
        if not normalized_value:
            continue
        decision = rate_limiter.enforce(
            scope_key=f"{action_name}:{dimension}:{normalized_value}",
            limit=limit,
            window_seconds=window_seconds,
            block_seconds=block_seconds,
        )
        if decision.allowed:
            continue
        retry_after_seconds = max(retry_after_seconds, decision.retry_after_seconds)

    if retry_after_seconds <= 0:
        return None
    return _rate_limited_response(
        action_name=action_name,
        retry_after_seconds=retry_after_seconds,
    )


def _handle_social_sign_in(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    try:
        body = _parse_body(event=event)
    except RequestBodyError as exc:
        response = _body_error_response(exc)
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=build_request_log_context(event, aws_context),
            error="request_body_invalid",
        )
        return response

    provider = str(body.get("provider") or "").strip().lower()
    if not provider:
        response = json_response(400, {"error": "provider is required."})
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=build_request_log_context(event, aws_context),
            error="missing_provider",
        )
        return response

    request_context = build_request_log_context(event, aws_context)
    request_context["project_id"] = provider
    rate_limited = _enforce_rate_limit(
        event=event,
        action_name="social_sign_in",
        body=body,
    )
    if rate_limited is not None:
        log_request_complete(
            started_at,
            status_code=rate_limited["statusCode"],
            request_context=request_context,
            error="rate_limited",
        )
        return rate_limited

    try:
        result = complete_social_sign_in(provider, body)
    except SocialAuthError as exc:
        response = json_response(
            exc.status_code,
            {
                "error": exc.message,
                "code": exc.code,
                **({"details": exc.details} if exc.details else {}),
            },
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error=exc.code,
        )
        return response
    except ValueError as exc:
        response = json_response(
            400,
            {"error": str(exc), "code": "SOCIAL_AUTH_INVALID"},
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="SOCIAL_AUTH_INVALID",
        )
        return response
    except Exception as exc:
        capture_exception(exc)
        response = json_response(
            500,
            {"error": "Social sign-in failed.", "code": "SOCIAL_AUTH_FAILED"},
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="SOCIAL_AUTH_FAILED",
        )
        return response

    response = json_response(200, result)
    log_request_complete(
        started_at,
        status_code=response["statusCode"],
        request_context=request_context,
    )
    return response


def _handle_email_sign_up(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    try:
        body = _parse_body(event=event)
    except RequestBodyError as exc:
        response = _body_error_response(exc)
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=build_request_log_context(event, aws_context),
            error="request_body_invalid",
        )
        return response

    request_context = build_request_log_context(event, aws_context)
    request_context["project_id"] = "sign_up"
    rate_limited = _enforce_rate_limit(
        event=event,
        action_name="sign_up",
        body=body,
    )
    if rate_limited is not None:
        log_request_complete(
            started_at,
            status_code=rate_limited["statusCode"],
            request_context=request_context,
            error="rate_limited",
        )
        return rate_limited
    try:
        result = register_email_account(
            repo,
            email=str(body.get("email") or ""),
            password=str(body.get("password") or ""),
            display_name=str(body.get("name") or body.get("display_name") or ""),
            given_name=str(body.get("given_name") or ""),
            family_name=str(body.get("family_name") or ""),
            birthdate=str(body.get("birthdate") or ""),
        )
    except AppUserAuthError as exc:
        response = json_response(
            exc.status_code,
            {
                "error": exc.message,
                "code": exc.code,
                **({"details": exc.details} if exc.details else {}),
            },
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error=exc.code,
        )
        return response
    except Exception:
        response = json_response(
            500,
            {"error": "Sign-up failed.", "code": "EMAIL_SIGN_UP_FAILED"},
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="EMAIL_SIGN_UP_FAILED",
        )
        return response

    response = json_response(200, result)
    log_request_complete(
        started_at,
        status_code=response["statusCode"],
        request_context=request_context,
    )
    return response


def _handle_confirm_sign_up(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="confirm_sign_up",
        action=lambda body, claims: confirm_email_account(
            repo,
            email=str(body.get("email") or ""),
            code=str(body.get("code") or ""),
            password=str(body.get("password") or ""),
        ),
    )


def _handle_resend_sign_up_code(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="resend_sign_up_code",
        action=lambda body, claims: resend_email_verification_code(
            repo,
            email=str(body.get("email") or ""),
        ),
    )


def _handle_request_password_reset(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="request_password_reset",
        action=lambda body, claims: request_password_reset(
            repo,
            email=str(body.get("email") or ""),
        ),
    )


def _handle_confirm_password_reset(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="confirm_password_reset",
        action=lambda body, claims: confirm_password_reset(
            repo,
            email=str(body.get("email") or ""),
            code=str(body.get("code") or ""),
            new_password=str(body.get("new_password") or body.get("newPassword") or ""),
        ),
    )


def _handle_refresh(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="refresh",
        action=lambda body, claims: refresh_session(
            repo,
            refresh_token=str(body.get("refresh_token") or body.get("refreshToken") or ""),
            fallback_token=str(
                body.get("fallback_id_token")
                or body.get("fallbackIdToken")
                or body.get("legacy_id_token")
                or body.get("legacyIdToken")
                or ""
            ),
        ),
    )


def _handle_change_password(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="change_password",
        require_auth=True,
        action=lambda body, claims: change_password(
            repo,
            user_id=str(claims.get("sub") or ""),
            current_password=str(body.get("current_password") or body.get("currentPassword") or ""),
            new_password=str(body.get("new_password") or body.get("newPassword") or ""),
        ),
    )


def _handle_resend_email_verification(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="resend_email_verification",
        require_auth=True,
        action=lambda body, claims: resend_email_verification_code(
            repo,
            user_id=str(claims.get("sub") or ""),
        ),
    )


def _handle_sign_out(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    return _handle_native_action(
        event,
        aws_context,
        action_name="sign_out",
        require_auth=True,
        action=lambda body, claims: sign_out_session(
            repo,
            session_id=str(claims.get("sid") or ""),
        ),
    )


def _handle_native_action(
    event: Dict[str, Any],
    aws_context: Any,
    *,
    action_name: str,
    action,
    require_auth: bool = False,
) -> Dict[str, Any]:
    started_at = time.perf_counter()
    request_context = build_request_log_context(event, aws_context)
    request_context["project_id"] = action_name

    claims = extract_claims_from_event(event) if require_auth else {}
    if require_auth and not str(claims.get("sub") or "").strip():
        response = unauthorized()
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="unauthorized",
        )
        return response

    try:
        body = _parse_body(event=event, allow_empty=True)
    except RequestBodyError as exc:
        response = _body_error_response(exc)
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="request_body_invalid",
        )
        return response

    rate_limited = _enforce_rate_limit(
        event=event,
        action_name=action_name,
        body=body,
        claims=claims,
    )
    if rate_limited is not None:
        log_request_complete(
            started_at,
            status_code=rate_limited["statusCode"],
            request_context=request_context,
            error="rate_limited",
        )
        return rate_limited

    try:
        result = action(body, claims)
    except AppUserAuthError as exc:
        response = json_response(
            exc.status_code,
            {
                "error": exc.message,
                "code": exc.code,
                **({"details": exc.details} if exc.details else {}),
            },
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error=exc.code,
        )
        return response
    except Exception as exc:
        capture_exception(exc)
        response = json_response(
            500,
            {"error": f"{action_name} failed.", "code": f"{action_name.upper()}_FAILED"},
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error=f"{action_name.upper()}_FAILED",
        )
        return response

    response = json_response(200, result)
    log_request_complete(
        started_at,
        status_code=response["statusCode"],
        request_context=request_context,
    )
    return response


def _handle_password_sign_in(event: Dict[str, Any], aws_context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    try:
        body = _parse_body(event=event)
    except RequestBodyError as exc:
        response = _body_error_response(exc)
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=build_request_log_context(event, aws_context),
            error="request_body_invalid",
        )
        return response

    identifier = str(body.get("identifier") or "").strip()
    password = str(body.get("password") or "")
    request_context = build_request_log_context(event, aws_context)
    request_context["project_id"] = "password"
    rate_limited = _enforce_rate_limit(
        event=event,
        action_name="password_sign_in",
        body=body,
    )
    if rate_limited is not None:
        log_request_complete(
            started_at,
            status_code=rate_limited["statusCode"],
            request_context=request_context,
            error="rate_limited",
        )
        return rate_limited

    try:
        result = complete_password_sign_in(identifier, password)
    except PasswordAuthError as exc:
        response = json_response(
            exc.status_code,
            {
                "error": exc.message,
                "code": exc.code,
                **({"details": exc.details} if exc.details else {}),
            },
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error=exc.code,
        )
        return response
    except Exception:
        response = json_response(
            500,
            {"error": "Sign-in failed.", "code": "PASSWORD_SIGN_IN_FAILED"},
        )
        log_request_complete(
            started_at,
            status_code=response["statusCode"],
            request_context=request_context,
            error="PASSWORD_SIGN_IN_FAILED",
        )
        return response

    response = json_response(200, result)
    log_request_complete(
        started_at,
        status_code=response["statusCode"],
        request_context=request_context,
    )
    return response


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    method = _method(event)

    if method == "POST" and path.endswith("/v1/auth/sign-up"):
        return _handle_email_sign_up(event, _context)
    if method == "POST" and path.endswith("/v1/auth/confirm-sign-up"):
        return _handle_confirm_sign_up(event, _context)
    if method == "POST" and path.endswith("/v1/auth/resend-sign-up-code"):
        return _handle_resend_sign_up_code(event, _context)
    if method == "POST" and path.endswith("/v1/auth/social/sign-in"):
        return _handle_social_sign_in(event, _context)
    if method == "POST" and path.endswith("/v1/auth/sign-in"):
        return _handle_password_sign_in(event, _context)
    if method == "POST" and path.endswith("/v1/auth/password-reset/request"):
        return _handle_request_password_reset(event, _context)
    if method == "POST" and path.endswith("/v1/auth/password-reset/confirm"):
        return _handle_confirm_password_reset(event, _context)
    if method == "POST" and path.endswith("/v1/auth/change-password"):
        return _handle_change_password(event, _context)
    if method == "POST" and path.endswith("/v1/auth/resend-email-verification"):
        return _handle_resend_email_verification(event, _context)
    if method == "POST" and path.endswith("/v1/auth/refresh"):
        return _handle_refresh(event, _context)
    if method == "POST" and path.endswith("/v1/auth/sign-out"):
        return _handle_sign_out(event, _context)

    return json_response(404, {"error": "Not found"})
