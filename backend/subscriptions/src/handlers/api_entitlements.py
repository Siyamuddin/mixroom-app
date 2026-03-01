from __future__ import annotations

from typing import Any, Dict

from common import config
from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.models import default_capabilities_for_tier, free_entitlement, normalize_tier
from common.repository import BillingRepository

repo = BillingRepository()


def _normalize_entitlement(raw: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    tier = normalize_tier(str(raw.get("tier") or "free"))
    capabilities = raw.get("capabilities") or {}
    if not isinstance(capabilities, dict):
        capabilities = {}
    if not capabilities:
        capabilities = default_capabilities_for_tier(tier, config.ALLOW_STUDIO_TIER)

    snapshot = {
        "user_id": user_id,
        "tier": tier,
        "status": raw.get("status") or "active",
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
    user_id = extract_user_id_from_event(event)
    if not user_id:
        return unauthorized()

    existing = repo.get_entitlement(user_id)
    if not existing:
        default_snapshot = free_entitlement(
            user_id=user_id,
            allow_studio_tier=config.ALLOW_STUDIO_TIER,
        ).to_dict()
        repo.put_entitlement(default_snapshot)
        return json_response(200, default_snapshot)

    return json_response(200, _normalize_entitlement(existing, user_id))
