from __future__ import annotations

import time
from typing import Any, Dict

from common import config
from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.models import (
    entitlement_capabilities_for_status,
    free_entitlement,
    normalize_status,
    normalize_tier,
    status_has_active_access,
)
from common.repository import BillingRepository

repo = BillingRepository()
init_sentry("mixroom-app-api-entitlements")


def _normalize_entitlement(raw: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    tier = normalize_tier(str(raw.get("tier") or "free"))
    status = normalize_status(str(raw.get("status") or "active"))
    capabilities = raw.get("capabilities") or {}
    if not isinstance(capabilities, dict) or not status_has_active_access(status):
        capabilities = entitlement_capabilities_for_status(
            tier,
            status,
            config.ALLOW_STUDIO_TIER,
        )

    snapshot = {
        "user_id": user_id,
        "tier": tier,
        "status": status,
        "effective_at": raw.get("effective_at"),
        "expires_at": raw.get("expires_at"),
        "source_provider": raw.get("source_provider") or "admin_grant",
        "source_subscription_id": raw.get("source_subscription_id") or "free-default",
        "capabilities": capabilities,
        "management_channel": raw.get("management_channel") or "free",
        "revision": int(raw.get("revision") or 0),
    }
    return snapshot


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    user_id = extract_user_id_from_event(event)
    request_context = build_request_log_context(event, _context, user_id=user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not user_id:
        return _finalize(unauthorized(), error="unauthorized")

    try:
        existing = repo.get_entitlement(user_id)
        if not existing:
            default_snapshot = free_entitlement(
                user_id=user_id,
                allow_studio_tier=config.ALLOW_STUDIO_TIER,
            ).to_dict()
            repo.put_entitlement(default_snapshot)
            return _finalize(json_response(200, default_snapshot))

        return _finalize(json_response(200, _normalize_entitlement(existing, user_id)))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "subscriptions_entitlements"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
