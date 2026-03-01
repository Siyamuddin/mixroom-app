from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Optional

TIERS = ("free", "pro", "studio")
PROVIDERS = ("apple", "google", "paddle", "toss", "admin_grant", "unknown")
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


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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
    )
