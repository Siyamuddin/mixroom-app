from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional
import uuid

from common import config
from common.models import free_entitlement
from common.repository import BillingRepository

repo = BillingRepository()


def _parse_ts(raw: Any) -> Optional[datetime]:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def handler(_event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
    scanned = 0
    downgraded = 0

    for sub in repo.scan_subscriptions():
        scanned += 1
        user_id = str(sub.get("user_id") or "").strip()
        sub_id = str(sub.get("subscription_id") or "").strip()
        if not user_id or not sub_id:
            continue

        expires_at = _parse_ts(sub.get("expires_at"))
        if not expires_at or expires_at > now:
            continue

        status = str(sub.get("status") or "").lower()
        if status in {"expired", "refunded", "revoked"}:
            continue

        updated_sub = dict(sub)
        updated_sub["status"] = "expired"
        repo.upsert_subscription(updated_sub)

        current_ent = repo.get_entitlement(user_id)
        if not current_ent:
            continue

        if str(current_ent.get("source_subscription_id") or "") != sub_id:
            continue

        revision = int(current_ent.get("revision") or 0) + 1
        free = free_entitlement(
            user_id=user_id,
            allow_studio_tier=config.ALLOW_STUDIO_TIER,
            revision=revision,
        ).to_dict()
        repo.put_entitlement(free)
        downgraded += 1

    repo.record_reconciliation_job(
        {
            "job_id": str(uuid.uuid4()),
            "job_type": "subscription_reconcile",
            "scanned": scanned,
            "downgraded": downgraded,
            "finished_at": datetime.now(timezone.utc).isoformat(),
        }
    )

    return {
        "statusCode": 200,
        "body": f"scanned={scanned}, downgraded={downgraded}",
    }
