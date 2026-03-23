from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


def main() -> int:
    try:
        from common import config  # noqa: E402
        from common.models import free_entitlement, normalize_status, normalize_tier  # noqa: E402
        from common.repository import BillingRepository  # noqa: E402
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "Missing runtime dependency for AWS entitlement backfill. Install backend app API dependencies first."
        ) from exc

    repo = BillingRepository()
    entitlements_by_user_id: dict[str, dict] = {}
    updated_existing = 0
    created_missing = 0

    for raw_item in repo.scan_entitlements():
        item = dict(raw_item or {})
        user_id = str(item.get("user_id") or "").strip()
        if not user_id:
            continue
        entitlements_by_user_id[user_id] = item
        tier_key = str(item.get("tier_key") or "").strip().lower()
        status_key = str(item.get("status_key") or "").strip().lower()
        normalized_tier = normalize_tier(str(item.get("tier") or "free"))
        normalized_status = normalize_status(str(item.get("status") or "active"))
        if tier_key == normalized_tier and status_key == normalized_status:
            continue
        item["tier_key"] = normalized_tier
        item["status_key"] = normalized_status
        repo.put_entitlement(item)
        updated_existing += 1

    for raw_user in repo.scan_users():
        user = dict(raw_user or {})
        user_id = str(user.get("user_id") or "").strip()
        if not user_id or user_id in entitlements_by_user_id:
            continue
        snapshot = free_entitlement(
            user_id=user_id,
            allow_studio_tier=config.ALLOW_STUDIO_TIER,
        ).to_dict()
        repo.put_entitlement(snapshot)
        created_missing += 1

    print(
        json.dumps(
            {
                "updated_existing": updated_existing,
                "created_missing": created_missing,
                "total_entitlements_after": len(entitlements_by_user_id)
                + created_missing,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
