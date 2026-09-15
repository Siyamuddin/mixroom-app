#!/usr/bin/env python3
"""Report producer-training ingestion health without exposing producer identity."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any


def summarize(items: list[dict[str, Any]], *, now: datetime) -> dict[str, Any]:
    active = [item for item in items if item.get("status") != "deleted"]
    statuses = Counter(str(item.get("ingestion_status") or "unknown") for item in active)
    cutoff = now - timedelta(hours=24)
    mature = []
    stale = []
    verified_states = {"ready_for_conversion", "converted"}
    for item in active:
        reserved_at = _parse_time(item.get("reserved_at") or item.get("updated_at"))
        if reserved_at is None or reserved_at > cutoff:
            continue
        mature.append(item)
        stored_at = _parse_time(item.get("stored_at"))
        verified_on_time = (
            str(item.get("ingestion_status") or "") in verified_states
            and stored_at is not None
            and stored_at - reserved_at <= timedelta(hours=24)
        )
        if not verified_on_time:
            stale.append(item)
    verified = len(mature) - len(stale)
    rate = 1.0 if not mature else verified / len(mature)
    return {
        "session_count": len(active),
        "deleted_session_count": len(items) - len(active),
        "ingestion_status_counts": dict(sorted(statuses.items())),
        "sessions_older_than_24h": len(mature),
        "verified_within_24h_count": verified,
        "stale_over_24h_count": len(stale),
        "verified_ingestion_rate": round(rate, 4),
        "meets_95_percent_sla": rate >= 0.95,
    }


def _parse_time(value: Any) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def _scan_table(table: Any) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    start_key = None
    while True:
        kwargs = {
            "ProjectionExpression": (
                "#status, ingestion_status, reserved_at, stored_at, updated_at"
            ),
            "ExpressionAttributeNames": {"#status": "status"},
        }
        if start_key:
            kwargs["ExclusiveStartKey"] = start_key
        response = table.scan(**kwargs)
        items.extend(response.get("Items") or [])
        start_key = response.get("LastEvaluatedKey")
        if not start_key:
            return items


def _object_count(client: Any, bucket: str, prefix: str) -> int:
    total = 0
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        total += int(page.get("KeyCount") or len(page.get("Contents") or []))
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--sessions-table", required=True)
    parser.add_argument("--region", default="ap-northeast-2")
    args = parser.parse_args()
    try:
        import boto3
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Install backend/training/requirements.txt before reporting."
        ) from exc
    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    s3 = boto3.client("s3", region_name=args.region)
    report = summarize(
        _scan_table(dynamodb.Table(args.sessions_table)),
        now=datetime.now(timezone.utc),
    )
    report["structured_object_count"] = _object_count(
        s3, args.bucket, "structured/"
    )
    report["pending_object_count"] = _object_count(s3, args.bucket, "pending/")
    report["media_object_count"] = _object_count(s3, args.bucket, "media/")
    print(json.dumps(report, indent=2, default=_json_default, sort_keys=True))
    return 0 if report["meets_95_percent_sla"] else 2


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(type(value).__name__)


if __name__ == "__main__":
    raise SystemExit(main())
