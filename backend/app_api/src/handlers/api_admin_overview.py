from __future__ import annotations

import time
from typing import Any, Dict

from common import config
from common.admin_access_repository import AdminAccessRepository
from common.admin_ai_access import can_edit_ai_settings
from common.admin_overview_repository import AdminOverviewRepository
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = AdminOverviewRepository()
access_repo = AdminAccessRepository()
init_sentry("mixroom-app-api-admin-overview")


def _limit_value(value: Any, *, default: int, maximum: int = 40) -> int:
    try:
        numeric = int(value or default)
    except (TypeError, ValueError):
        numeric = default
    return max(1, min(numeric, maximum))


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
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
    request_context = build_request_log_context(event, _context, user_id=user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not admin_client_id or not admin_user_pool_id:
        return _finalize(json_response(404, {"error": "Not found"}), error="disabled")

    if not user_id or not email:
        return _finalize(
            unauthorized("Employee sign-in required."),
            error="unauthorized",
        )

    if not access_repo.is_email_allowed(email):
        return _finalize(
            json_response(403, {"error": "Email is not allowlisted for admin access."}),
            error="not_allowlisted",
        )

    try:
        query = event.get("queryStringParameters") or {}
        user_limit = _limit_value(
            query.get("user_limit") if isinstance(query, dict) else None,
            default=8,
        )
        project_limit = _limit_value(
            query.get("project_limit") if isinstance(query, dict) else None,
            default=8,
        )
        overview = repo.build_overview(
            user_limit=user_limit,
            project_limit=project_limit,
        )
        overview["requested_by"] = user_id
        overview["requested_email"] = email
        overview["permissions"] = {
            "can_edit_ai_settings": can_edit_ai_settings(email),
            "can_grant_ai_prompts": can_edit_ai_settings(email),
        }
        return _finalize(json_response(200, overview))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "subscriptions_admin_overview"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
