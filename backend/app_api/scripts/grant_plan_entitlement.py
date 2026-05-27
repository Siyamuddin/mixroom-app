from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common.models import (  # noqa: E402
    PLAN_CODES,
    default_capabilities_for_plan,
    normalize_plan_code,
    normalize_status,
    status_has_active_access,
)


_PLAN_METADATA = {
    "free": ("Free", "individual"),
    "starter": ("Starter", "individual"),
    "producer": ("Producer", "individual"),
    "studio": ("Studio", "team"),
    "enterprise": ("Enterprise", "enterprise"),
    "education": ("Education", "education"),
}


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _table_name(kind: str, stage: str) -> str:
    if kind == "entitlements":
        return f"mixroom-entitlements-current-{stage}"
    if kind == "subscriptions":
        return f"mixroom-subscriptions-{stage}"
    raise ValueError(f"Unknown table kind: {kind}")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Grant a Mixroom plan entitlement to a user for local/dev testing.",
    )
    parser.add_argument("--user-id", required=True)
    parser.add_argument("--plan-code", required=True, choices=PLAN_CODES)
    parser.add_argument("--status", default="active")
    parser.add_argument("--stage", default="prod")
    parser.add_argument("--region", default="ap-northeast-2")
    parser.add_argument("--profile", default="")
    parser.add_argument("--entitlements-table", default="")
    parser.add_argument("--subscriptions-table", default="")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    user_id = str(args.user_id or "").strip()
    plan_code = normalize_plan_code(args.plan_code)
    status = normalize_status(args.status)
    if not user_id:
        raise SystemExit("--user-id is required.")
    if plan_code not in PLAN_CODES:
        raise SystemExit(f"--plan-code must be one of: {', '.join(PLAN_CODES)}")

    try:
        import boto3
    except ModuleNotFoundError as exc:
        raise SystemExit("boto3 is required to grant a live entitlement.") from exc

    session_kwargs: dict[str, Any] = {"region_name": args.region}
    if args.profile:
        session_kwargs["profile_name"] = args.profile
    ddb = boto3.Session(**session_kwargs).resource("dynamodb")

    now = _utc_now_iso()
    existing = (
        ddb.Table(args.entitlements_table or _table_name("entitlements", args.stage))
        .get_item(Key={"user_id": user_id})
        .get("Item")
        or {}
    )
    revision = int(existing.get("revision") or 0) + 1
    label, group = _PLAN_METADATA[plan_code]
    subscription_id = f"admin_grant:{user_id}:{plan_code}"
    entitlement = {
        "user_id": user_id,
        "status": status,
        "effective_at": now,
        "expires_at": None,
        "source_provider": "admin_grant",
        "source_subscription_id": "free-default" if plan_code == "free" else subscription_id,
        "capabilities": default_capabilities_for_plan(
            plan_code if status_has_active_access(status) else "free"
        ),
        "management_channel": "admin",
        "revision": revision,
        "plan_code": plan_code,
        "plan_label": label,
        "plan_group": group,
        "updated_at": now,
        "status_key": status,
        "tier_key": plan_code,
    }

    entitlements = ddb.Table(
        args.entitlements_table or _table_name("entitlements", args.stage)
    )
    entitlements.put_item(Item=entitlement)

    if plan_code != "free":
        subscription = {
            "subscription_id": subscription_id,
            "user_id": user_id,
            "provider": "admin_grant",
            "plan_code": plan_code,
            "status": status,
            "effective_at": now,
            "expires_at": None,
            "product_id": "",
            "product_code": f"{plan_code}_admin_grant",
            "management_channel": "admin",
            "source_event_id": "",
            "source_occurred_at": now,
            "updated_at": now,
        }
        ddb.Table(args.subscriptions_table or _table_name("subscriptions", args.stage)).put_item(
            Item=subscription
        )

    print(
        json.dumps(
            {
                "user_id": user_id,
                "plan_code": plan_code,
                "status": status,
                "revision": revision,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
