from __future__ import annotations

import time
from typing import Any, Dict

from common import config
from common.admin_access_repository import AdminAccessRepository
from common.admin_ai_access import can_edit_ai_settings
from common.admin_user_repository import (
    AdminDeleteRequiresForceError,
    AdminUserNotFoundError,
    AdminUserRepository,
)
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = AdminUserRepository()
access_repo = AdminAccessRepository()
init_sentry("mixroom-app-api-admin-users")


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _admin_identity(event: Dict[str, Any]) -> tuple[str, str, str]:
    admin_client_id = (
        config.ADMIN_COGNITO_APP_CLIENT_ID or config.COGNITO_APP_CLIENT_ID
    ).strip()
    admin_user_pool_id = (
        config.ADMIN_COGNITO_USER_POOL_ID or config.COGNITO_USER_POOL_ID
    ).strip()
    try:
        claims = extract_claims_from_event(
            event,
            audiences=[admin_client_id],
            user_pool_ids=[admin_user_pool_id],
            allow_native=False,
            allow_cognito=True,
        )
    except TypeError:
        claims = extract_claims_from_event(
            event,
            audiences=[admin_client_id],
            user_pool_ids=[admin_user_pool_id],
        )
    user_id = str(claims.get("sub") or "").strip()
    email = str(claims.get("email") or "").strip().lower()
    return admin_client_id if admin_user_pool_id else "", user_id, email


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    admin_client_id, admin_user_id, admin_email = _admin_identity(event)
    request_context = build_request_log_context(event, _context, user_id=admin_user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not admin_client_id:
        return _finalize(json_response(404, {"error": "Not found"}), error="disabled")

    if not admin_user_id or not admin_email:
        return _finalize(
            unauthorized("Employee sign-in required."),
            error="unauthorized",
        )

    if not access_repo.is_email_allowed(admin_email):
        return _finalize(
            json_response(403, {"error": "Email is not allowlisted for admin access."}),
            error="not_allowlisted",
        )

    path = _path(event)
    method = _method(event)
    try:
        if method == "GET" and path.endswith("/v1/internal/admin/users"):
            query = event.get("queryStringParameters") or {}
            payload = repo.search_users(
                query=str((query.get("query") if isinstance(query, dict) else "") or ""),
                limit=(query.get("limit") if isinstance(query, dict) else None) or 24,
                subscription_filter=str(
                    (
                        query.get("subscription_filter")
                        if isinstance(query, dict)
                        else ""
                    )
                    or "all"
                ),
            )
            payload["requested_by"] = admin_user_id
            payload["requested_email"] = admin_email
            return _finalize(json_response(200, payload))

        if method == "POST" and path.endswith("/v1/internal/admin/users/create-username-account"):
            try:
                body = parse_json_body(event)
            except RequestBodyError as exc:
                return _finalize(
                    json_response(exc.status_code, {"error": exc.message}),
                    error="request_body_invalid",
                )

            payload = repo.create_username_account(
                username=str(body.get("username") or ""),
                display_name=str(
                    body.get("display_name")
                    or body.get("displayName")
                    or body.get("name")
                    or ""
                ),
                password=str(body.get("password") or ""),
                email=str(body.get("email") or ""),
                created_by_user_id=admin_user_id,
                created_by_email=admin_email,
            )
            return _finalize(json_response(200, payload))

        if method == "POST" and path.endswith("/v1/internal/admin/users/delete"):
            try:
                body = parse_json_body(event)
            except RequestBodyError as exc:
                return _finalize(
                    json_response(exc.status_code, {"error": exc.message}),
                    error="request_body_invalid",
                )

            deletion = repo.delete_user(
                user_id=str(body.get("user_id") or ""),
                deleted_by_user_id=admin_user_id,
                deleted_by_email=admin_email,
                reason=str(body.get("reason") or ""),
                confirm_email=str(body.get("confirm_email") or body.get("confirmEmail") or ""),
                force=bool(body.get("force")),
            )
            return _finalize(json_response(200, deletion))

        if method == "POST" and path.endswith("/v1/internal/admin/users/grant-prompts"):
            if not can_edit_ai_settings(admin_email):
                return _finalize(
                    json_response(
                        403,
                        {"error": "Only andrew@mixroom.ai can edit AI settings or grant AI prompts."},
                    ),
                    error="ai_editor_required",
                )
            try:
                body = parse_json_body(event)
            except RequestBodyError as exc:
                return _finalize(
                    json_response(exc.status_code, {"error": exc.message}),
                    error="request_body_invalid",
                )

            payload = repo.grant_prompt_allowance(
                user_id=str(body.get("user_id") or ""),
                prompt_count=body.get("prompt_count"),
                granted_by_user_id=admin_user_id,
                granted_by_email=admin_email,
            )
            return _finalize(json_response(200, payload))

        if method == "POST" and path.endswith("/v1/internal/admin/users/entitlement-override"):
            try:
                body = parse_json_body(event)
            except RequestBodyError as exc:
                return _finalize(
                    json_response(exc.status_code, {"error": exc.message}),
                    error="request_body_invalid",
                )

            payload = repo.apply_entitlement_override(
                user_id=str(body.get("user_id") or ""),
                plan_code=str(body.get("plan_code") or body.get("planCode") or ""),
                expires_at=str(body.get("expires_at") or body.get("expiresAt") or ""),
                reason=str(body.get("reason") or ""),
                confirm_identifier=str(
                    body.get("confirm_identifier")
                    or body.get("confirmIdentifier")
                    or ""
                ),
                confirm_admin_first_name=str(
                    body.get("confirm_admin_first_name")
                    or body.get("confirmAdminFirstName")
                    or ""
                ),
                seat_limit=body.get("seat_limit") or body.get("seatLimit"),
                organization_name=str(
                    body.get("organization_name")
                    or body.get("organizationName")
                    or ""
                ),
                granted_by_user_id=admin_user_id,
                granted_by_email=admin_email,
            )
            return _finalize(json_response(200, payload))
    except ValueError as exc:
        return _finalize(json_response(400, {"error": str(exc)}), error="bad_request")
    except AdminUserNotFoundError as exc:
        return _finalize(json_response(404, {"error": str(exc)}), error="not_found")
    except AdminDeleteRequiresForceError as exc:
        return _finalize(
            json_response(
                409,
                {
                    "error": str(exc),
                    "requires_force": True,
                    "user": exc.snapshot,
                },
            ),
            error="requires_force",
        )
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "admin_users"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )

    return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
