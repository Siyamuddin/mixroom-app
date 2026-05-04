from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, Optional

TIERS = ("free", "pro", "studio")
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
ACTIVE_ACCESS_STATUSES = {"trialing", "active", "grace_period"}
_TIER_PRIORITY = {"free": 0, "pro": 1, "studio": 2}
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


def normalize_tier(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value in TIERS:
        return value
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


def subscription_priority_key(raw: Dict[str, Any]) -> tuple[int, int, int, datetime, datetime]:
    tier = normalize_tier(str(raw.get("tier") or "free"))
    status = normalize_status(str(raw.get("status") or "expired"))
    active_access = 1 if status_has_active_access(status) else 0
    tier_priority = _TIER_PRIORITY.get(tier, 0)
    status_priority = _STATUS_PRIORITY.get(status, -10)

    expires_at = _parse_datetime(raw.get("expires_at"))
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
        tier_priority,
        status_priority,
        expires_at,
        activity_at,
    )


def choose_primary_subscription(subscriptions: Iterable[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    candidates = [item for item in subscriptions if isinstance(item, dict)]
    if not candidates:
        return None
    return max(candidates, key=subscription_priority_key)


def default_capabilities_for_tier(tier: str, allow_studio_tier: bool) -> Dict[str, bool]:
    free = {
        "pro_editor": False,
        "unlimited_audio_tracks": False,
        "multi_video_import": False,
        "premium_effects": False,
        "video_projects": True,
        "web_checkout": True,
        "mobile_iap": True,
        "studio_features": False,
    }
    if tier == "pro":
        return {
            **free,
            "pro_editor": True,
            "unlimited_audio_tracks": True,
            "multi_video_import": True,
            "premium_effects": True,
        }
    if tier == "studio":
        return {
            **free,
            "pro_editor": True,
            "unlimited_audio_tracks": True,
            "multi_video_import": True,
            "premium_effects": True,
            "studio_features": allow_studio_tier,
        }
    return free


def infer_tier_from_product_id(product_id: str) -> str:
    value = (product_id or "").strip().lower()
    if not value:
        return "free"
    if "studio" in value:
        return "studio"
    if "pro" in value or "premium" in value:
        return "pro"
    return "free"


def entitlement_capabilities_for_status(
    tier: str,
    status: str,
    allow_studio_tier: bool,
) -> Dict[str, bool]:
    if not status_has_active_access(status):
        return default_capabilities_for_tier("free", allow_studio_tier)
    return default_capabilities_for_tier(normalize_tier(tier), allow_studio_tier)


@dataclass
class EntitlementSnapshot:
    user_id: str
    tier: str
    status: str
    effective_at: str
    expires_at: Optional[str]
    source_provider: str
    source_subscription_id: str
    capabilities: Dict[str, bool]
    management_channel: str
    revision: int
    plan_code: str = "free"
    plan_label: str = "Free"
    plan_group: str = "individual"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "user_id": self.user_id,
            "tier": self.tier,
            "status": self.status,
            "effective_at": self.effective_at,
            "expires_at": self.expires_at,
            "source_provider": self.source_provider,
            "source_subscription_id": self.source_subscription_id,
            "capabilities": self.capabilities,
            "management_channel": self.management_channel,
            "revision": self.revision,
            "plan_code": self.plan_code,
            "plan_label": self.plan_label,
            "plan_group": self.plan_group,
        }


def free_entitlement(user_id: str, allow_studio_tier: bool, revision: int = 0) -> EntitlementSnapshot:
    return EntitlementSnapshot(
        user_id=user_id,
        tier="free",
        status="active",
        effective_at=utc_now_iso(),
        expires_at=None,
        source_provider="admin_grant",
        source_subscription_id="free-default",
        capabilities=default_capabilities_for_tier("free", allow_studio_tier),
        management_channel="free",
        revision=revision,
        plan_code="free",
        plan_label="Free",
        plan_group="individual",
    )
