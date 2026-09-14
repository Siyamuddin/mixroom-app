from __future__ import annotations

import hmac
import time
from typing import Any, Dict

from common import config
from common.admin_access_repository import AdminAccessRepository
from common.admin_ai_access import can_edit_ai_settings
from common.admin_overview_repository import AdminOverviewRepository
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.secrets import get_parameter_string

repo = AdminOverviewRepository()
access_repo = AdminAccessRepository()
init_sentry("mixroom-app-api-admin-overview")

_COMPANY_DASHBOARD_CACHE_TTL_SECONDS = 300
_company_dashboard_cache: tuple[float, Dict[str, Any]] | None = None


def _limit_value(value: Any, *, default: int, maximum: int = 40) -> int:
    try:
        numeric = int(value or default)
    except (TypeError, ValueError):
        numeric = default
    return max(1, min(numeric, maximum))


def _tool_usage_range_value(value: Any, *, default: str = "30d") -> str:
    normalized = str(value or default).strip().lower()
    if normalized in {"7d", "30d", "all"}:
        return normalized
    return default


def _include_section_value(value: Any, *, default: bool = True) -> bool:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "").strip()


def _company_dashboard_token(event: Dict[str, Any]) -> str:
    headers = event.get("headers") or {}
    normalized_headers = {
        str(key).lower(): str(value or "")
        for key, value in headers.items()
    }
    header_token = normalized_headers.get("x-company-dashboard-key", "").strip()
    if header_token:
        return header_token
    authorization = str(
        headers.get("authorization") or headers.get("Authorization") or ""
    ).strip()
    prefix = "Bearer "
    if not authorization.startswith(prefix):
        return ""
    return authorization[len(prefix):].strip()


def _is_company_dashboard_request(event: Dict[str, Any]) -> bool:
    return _path(event).endswith("/company-dashboard/summary")


def _is_authorized_company_dashboard_request(event: Dict[str, Any]) -> bool:
    configured_parameter = config.COMPANY_DASHBOARD_API_KEY_PARAMETER_NAME
    token = _company_dashboard_token(event)
    if not configured_parameter or not token:
        return False
    try:
        expected = get_parameter_string(configured_parameter)
    except Exception:
        return False
    return bool(expected) and hmac.compare_digest(token, expected)


def _company_dashboard_summary() -> Dict[str, Any]:
    global _company_dashboard_cache
    now = time.monotonic()
    cached = _company_dashboard_cache
    if cached is not None and now - cached[0] < _COMPANY_DASHBOARD_CACHE_TTL_SECONDS:
        return cached[1]

    overview = repo.build_overview(
        include_ai_usage=True,
        include_product_analytics=True,
        include_ai_observability=False,
        include_users=False,
        include_projects=False,
        tool_usage_range="30d",
    )
    summary = overview.get("summary") or {}
    product_analytics = overview.get("product_analytics") or {}
    summary_keys = (
        "total_users",
        "tracked_users",
        "paid_users",
        "active_subscriptions",
        "paid_conversion_rate",
        "granted_premium_users",
        "premium_users",
        "trial_users",
        "unattributed_premium_users",
        "ai_prompts_today",
        "ai_prompts_week",
        "ai_active_users_today",
        "ai_active_users_week",
        "avg_prompts_per_user_today",
        "avg_prompts_per_user_week",
        "avg_latency_ms_today",
        "avg_latency_ms_week",
        "ai_success_rate_week",
    )
    payload = {
        "schema_version": 1,
        "generated_at": overview.get("generated_at"),
        "summary": {key: summary.get(key) for key in summary_keys},
        "subscription_tiers": overview.get("subscription_tiers") or [],
        "product_analytics": {
            "source": product_analytics.get("source"),
            "status": product_analytics.get("status"),
            "updated_at": product_analytics.get("updated_at"),
            "metrics": product_analytics.get("metrics") or {},
            "daily_active_users": product_analytics.get("daily_active_users") or [],
            "daily_hours_used": product_analytics.get("daily_hours_used") or [],
            "top_countries": product_analytics.get("top_countries") or [],
        },
        "warnings": overview.get("warnings") or [],
    }
    _company_dashboard_cache = (now, payload)
    return payload


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    if _is_company_dashboard_request(event):
        request_context = build_request_log_context(event, _context)
        if not _is_authorized_company_dashboard_request(event):
            log_request_complete(
                started_at,
                status_code=401,
                request_context=request_context,
                error="unauthorized_company_dashboard",
            )
            return unauthorized("Company dashboard authorization required.")
        try:
            payload = _company_dashboard_summary()
            log_request_complete(
                started_at,
                status_code=200,
                request_context=request_context,
            )
            return json_response(
                200,
                payload,
                headers={"Cache-Control": "private, max-age=300"},
            )
        except Exception as exc:
            capture_exception(
                exc,
                context=request_context,
                tags={"service": "company_dashboard_summary"},
            )
            log_request_complete(
                started_at,
                status_code=500,
                request_context=request_context,
                error="internal_server_error",
            )
            return json_response(500, {"error": "Internal server error"})

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
        if _path(event).endswith("/live-presence"):
            payload = repo.build_live_presence()
            payload["requested_by"] = user_id
            payload["requested_email"] = email
            return _finalize(json_response(200, payload))

        query = event.get("queryStringParameters") or {}
        user_limit = _limit_value(
            query.get("user_limit") if isinstance(query, dict) else None,
            default=8,
        )
        project_limit = _limit_value(
            query.get("project_limit") if isinstance(query, dict) else None,
            default=8,
        )
        trace_limit = _limit_value(
            query.get("trace_limit") if isinstance(query, dict) else None,
            default=6,
            maximum=24,
        )
        include_ai_usage = _include_section_value(
            query.get("include_ai_usage") if isinstance(query, dict) else None,
            default=True,
        )
        include_product_analytics = _include_section_value(
            query.get("include_product_analytics") if isinstance(query, dict) else None,
            default=True,
        )
        include_ai_observability = _include_section_value(
            query.get("include_ai_observability") if isinstance(query, dict) else None,
            default=True,
        )
        include_users = _include_section_value(
            query.get("include_users") if isinstance(query, dict) else None,
            default=True,
        )
        include_projects = _include_section_value(
            query.get("include_projects") if isinstance(query, dict) else None,
            default=True,
        )
        tool_usage_range = _tool_usage_range_value(
            query.get("tool_usage_range") if isinstance(query, dict) else None,
            default="30d",
        )
        overview = repo.build_overview(
            user_limit=user_limit,
            project_limit=project_limit,
            trace_limit=trace_limit,
            include_ai_usage=include_ai_usage,
            include_product_analytics=include_product_analytics,
            include_ai_observability=include_ai_observability,
            include_users=include_users,
            include_projects=include_projects,
            tool_usage_range=tool_usage_range,
        )
        overview["requested_by"] = user_id
        overview["requested_email"] = email
        overview["permissions"] = {
            "can_edit_ai_settings": can_edit_ai_settings(email),
            "can_grant_ai_prompts": can_edit_ai_settings(email),
            "can_apply_entitlement_overrides": True,
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
