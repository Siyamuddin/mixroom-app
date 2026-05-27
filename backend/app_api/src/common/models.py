from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import re
from typing import Any, Dict, Iterable, Optional

from .plan_catalog import (
    PLAN_CODES,
    INDIVIDUAL_PLAN_CODES,
    PLAN_PRIORITY,
    TEAM_BUSINESS_PLAN_CODES,
    default_capabilities_for_plan,
    default_limits_for_plan,
)

PROVIDERS = ("apple", "google", "kakao", "paddle", "toss", "admin_grant", "unknown")
STATUSES = (
    "trialing",
    "active",
    "grace_period",
    "past_due",
    "paused",
    "canceled",
    "expired",
    "refunded",
    "revoked",
)
ACTIVE_ACCESS_STATUSES = {"trialing", "active", "grace_period", "past_due"}
_PLAN_CODE_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
_STATUS_PRIORITY = {
    "trialing": 4,
    "active": 3,
    "grace_period": 2,
    "past_due": 1,
    "paused": 0,
    "canceled": 0,
    "expired": -1,
    "refunded": -2,
    "revoked": -2,
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_datetime(raw: Any) -> Optional[datetime]:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw.astimezone(timezone.utc)

    text = str(raw).strip()
    if not text:
        return None
    if text.isdigit():
        numeric = int(text)
        if numeric > 9999999999:
            return datetime.fromtimestamp(numeric / 1000.0, tz=timezone.utc)
        return datetime.fromtimestamp(numeric, tz=timezone.utc)
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def normalize_plan_code(raw: Any) -> str:
    value = str(raw or "").strip().lower()
    if value == "pro":
        return "producer"
    if value == "basic":
        return "free"
    if _PLAN_CODE_RE.match(value):
        return value
    return "free"


def legacy_tier_for_plan_code(raw: Any) -> str:
    value = normalize_plan_code(raw)
    if value in TEAM_BUSINESS_PLAN_CODES:
        return "studio"
    if value in INDIVIDUAL_PLAN_CODES and value != "free":
        return "pro"
    return "free"


def normalize_provider(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value in PROVIDERS:
        return value
    return "unknown"


def normalize_status(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value in STATUSES:
        return value
    return "expired"


def status_has_active_access(raw: str) -> bool:
    return normalize_status(raw) in ACTIVE_ACCESS_STATUSES


def subscription_effective_status(raw: Dict[str, Any]) -> str:
    status = normalize_status(str(raw.get("status") or "expired"))
    expires_at = _parse_datetime(raw.get("expires_at") or raw.get("current_period_end"))
    if status_has_active_access(status) and expires_at is not None and expires_at <= datetime.now(timezone.utc):
        return "expired"
    return status


def subscription_priority_key(raw: Dict[str, Any]) -> tuple[int, int, int, datetime, datetime]:
    plan_code = normalize_plan_code(raw.get("plan_code") or raw.get("tier") or "free")
    status = subscription_effective_status(raw)
    expires_at = _parse_datetime(raw.get("expires_at"))
    active_access = 1 if status_has_active_access(status) else 0
    plan_priority = PLAN_PRIORITY.get(plan_code, PLAN_PRIORITY["producer"]) if active_access else 0
    status_priority = _STATUS_PRIORITY.get(status, -10)

    if expires_at is None:
        expires_at = datetime.max.replace(tzinfo=timezone.utc) if active_access else datetime.min.replace(tzinfo=timezone.utc)

    activity_at = _parse_datetime(
        raw.get("source_occurred_at")
        or raw.get("updated_at")
        or raw.get("effective_at")
        or raw.get("created_at")
    ) or datetime.min.replace(tzinfo=timezone.utc)

    return (
        active_access,
        plan_priority,
        status_priority,
        expires_at,
        activity_at,
    )


def choose_primary_subscription(subscriptions: Iterable[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    candidates = [item for item in subscriptions if isinstance(item, dict)]
    if not candidates:
        return None
    return max(candidates, key=subscription_priority_key)


def entitlement_capabilities_for_status(plan_code: str, status: str) -> Dict[str, bool]:
    if not status_has_active_access(status):
        return default_capabilities_for_plan("free")
    return default_capabilities_for_plan(plan_code)


def entitlement_limits_for_status(plan_code: str, status: str) -> Dict[str, Any]:
    if not status_has_active_access(status):
        return default_limits_for_plan("free")
    return default_limits_for_plan(plan_code)


@dataclass
class EntitlementSnapshot:
    user_id: str
    status: str
    effective_at: str
    expires_at: Optional[str]
    source_provider: str
    source_subscription_id: str
    capabilities: Dict[str, bool]
    limits: Dict[str, Any]
    management_channel: str
    revision: int
    plan_code: str = "free"
    plan_label: str = "Free"
    plan_group: str = "individual"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "user_id": self.user_id,
            "tier": legacy_tier_for_plan_code(self.plan_code),
            "status": self.status,
            "effective_at": self.effective_at,
            "expires_at": self.expires_at,
            "source_provider": self.source_provider,
            "source_subscription_id": self.source_subscription_id,
            "capabilities": self.capabilities,
            "limits": self.limits,
            "management_channel": self.management_channel,
            "revision": self.revision,
            "plan_code": self.plan_code,
            "plan_label": self.plan_label,
            "plan_group": self.plan_group,
        }


def free_entitlement(user_id: str, revision: int = 0) -> EntitlementSnapshot:
    return EntitlementSnapshot(
        user_id=user_id,
        status="active",
        effective_at=utc_now_iso(),
        expires_at=None,
        source_provider="admin_grant",
        source_subscription_id="free-default",
        capabilities=default_capabilities_for_plan("free"),
        limits=default_limits_for_plan("free"),
        management_channel="free",
        revision=revision,
        plan_code="free",
        plan_label="Free",
        plan_group="individual",
    )
