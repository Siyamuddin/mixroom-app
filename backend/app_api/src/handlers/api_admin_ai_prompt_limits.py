from __future__ import annotations

import time
from typing import Any, Dict

from common import config
from common.admin_access_repository import AdminAccessRepository
from common.admin_ai_access import can_edit_ai_settings
from common.admin_ai_prompt_limits_repository import AdminAiPromptLimitsRepository
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = AdminAiPromptLimitsRepository()
access_repo = AdminAccessRepository()
init_sentry("mixroom-app-api-admin-ai-prompt-limits")


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
        if path.endswith("/v1/internal/admin/settings/ai-prompt-limits"):
            if method == "GET":
                payload = {
                    "settings": repo.get_prompt_limits(),
                    "defaults": repo.get_default_prompt_limits(),
                    "can_edit": can_edit_ai_settings(admin_email),
                    "requested_by": admin_user_id,
                    "requested_email": admin_email,
                }
                return _finalize(json_response(200, payload))

            if method == "DELETE":
                if not can_edit_ai_settings(admin_email):
                    return _finalize(
                        json_response(
                            403,
                            {"error": "Only andrew@mixroom.ai can edit AI settings or grant AI prompts."},
                        ),
                        error="ai_editor_required",
                    )
                payload = {
                    "settings": repo.clear_prompt_limits(),
                    "defaults": repo.get_default_prompt_limits(),
                    "updated_by": admin_user_id,
                    "updated_email": admin_email,
                }
                return _finalize(json_response(200, payload))

            if method == "PUT":
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
                payload = {
                    "settings": repo.update_prompt_limits(
                        free_daily_prompt_limit=body.get("free_daily_prompt_limit"),
                        free_weekly_prompt_limit=body.get("free_weekly_prompt_limit"),
                        updated_by_user_id=admin_user_id,
                        updated_by_email=admin_email,
                    ),
                    "updated_by": admin_user_id,
                    "updated_email": admin_email,
                }
                return _finalize(json_response(200, payload))
    except ValueError as exc:
        return _finalize(json_response(400, {"error": str(exc)}), error="bad_request")
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "admin_ai_prompt_limits"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )

    return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
