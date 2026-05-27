#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional

ACTIVE_ACCESS_STATUSES = {"trialing", "active", "grace_period"}
AT_RISK_STATUSES = {"grace_period", "past_due", "paused", "canceled"}
CHURNED_STATUSES = {"expired", "refunded", "revoked"}


def _scan_table(table: Any) -> Iterable[Dict[str, Any]]:
    start_key = None
    while True:
        kwargs: Dict[str, Any] = {}
        if start_key:
            kwargs["ExclusiveStartKey"] = start_key
        response = table.scan(**kwargs)
        for item in response.get("Items", []):
            yield item
        start_key = response.get("LastEvaluatedKey")
        if not start_key:
            break


def _parse_dt(raw: Any) -> Optional[datetime]:
    text = str(raw or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def _status_has_active_access(raw: Any) -> bool:
    return str(raw or "").strip().lower() in ACTIVE_ACCESS_STATUSES


def _summarize_entitlements(items: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_status = Counter()
    by_provider = Counter()
    active_paid_by_plan = Counter()

    active_access_users = 0
    active_paid_users = 0
    at_risk_users = 0

    for item in items:
        status = str(item.get("status") or "unknown").strip().lower()
        plan_code = str(item.get("plan_code") or "free").strip().lower()
        provider = str(item.get("source_provider") or "unknown").strip().lower()

        by_status[status] += 1
        by_provider[provider] += 1

        if _status_has_active_access(status):
            active_access_users += 1
            if plan_code != "free":
                active_paid_users += 1
                active_paid_by_plan[plan_code] += 1

        if status in AT_RISK_STATUSES:
            at_risk_users += 1

    return {
        "total_users": len(items),
        "active_access_users": active_access_users,
        "active_paid_users": active_paid_users,
        "at_risk_users": at_risk_users,
        "by_status": dict(by_status),
        "by_source_provider": dict(by_provider),
        "active_paid_by_plan": dict(active_paid_by_plan),
    }


def _summarize_recent_events(
    items: List[Dict[str, Any]],
    *,
    since: Optional[datetime],
) -> Dict[str, Any]:
    filtered: List[Dict[str, Any]] = []
    for item in items:
        occurred = _parse_dt(item.get("occurred_at") or item.get("created_at"))
        if since is not None and occurred is not None and occurred < since:
            continue
        if since is not None and occurred is None:
            continue
        filtered.append(item)

    by_provider = Counter()
    by_event_type = Counter()
    by_status = Counter()

    for item in filtered:
        provider = str(item.get("provider") or "unknown").strip().lower()
        event_type = str(item.get("event_type") or "unknown").strip().lower()
        normalized = item.get("normalized") or {}
        status = "unknown"
        if isinstance(normalized, dict):
            status = str(normalized.get("status") or "unknown").strip().lower()

        by_provider[provider] += 1
        by_event_type[event_type] += 1
        by_status[status] += 1

    return {
        "window_days": None if since is None else int((datetime.now(timezone.utc) - since).days),
        "total_events": len(filtered),
        "by_provider": dict(by_provider),
        "by_event_type": dict(by_event_type),
        "normalized_status_counts": dict(by_status),
        "rough_churn_events": sum(by_status[s] for s in CHURNED_STATUSES),
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Print a rough subscription KPI snapshot from the AWS DynamoDB tables."
        )
    )
    parser.add_argument(
        "--stage",
        default="prod",
        help="Stage suffix used when deriving table names.",
    )
    parser.add_argument(
        "--events-table",
        default="",
        help="Override the billing events table name.",
    )
    parser.add_argument(
        "--entitlements-table",
        default="",
        help="Override the entitlements table name.",
    )
    parser.add_argument(
        "--since-days",
        type=int,
        default=30,
        help="Recent event window. Use 0 to include all events.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON instead of a human-readable summary.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    try:
        import boto3
    except ImportError:
        print("boto3 is required to read AWS tables.", file=sys.stderr)
        return 2

    stage = args.stage
    events_table_name = args.events_table or f"mixroom-billing-events-{stage}"
    entitlements_table_name = (
        args.entitlements_table or f"mixroom-entitlements-current-{stage}"
    )

    dynamodb = boto3.resource("dynamodb")
    events_table = dynamodb.Table(events_table_name)
    entitlements_table = dynamodb.Table(entitlements_table_name)

    entitlements = list(_scan_table(entitlements_table))
    events = list(_scan_table(events_table))

    since = None
    if args.since_days > 0:
        since = datetime.now(timezone.utc) - timedelta(days=args.since_days)

    payload = {
        "entitlements_table": entitlements_table_name,
        "events_table": events_table_name,
        "current_entitlements": _summarize_entitlements(entitlements),
        "recent_events": _summarize_recent_events(events, since=since),
    }

    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    current = payload["current_entitlements"]
    recent = payload["recent_events"]
    print(f"Entitlements table: {entitlements_table_name}")
    print(f"Events table: {events_table_name}")
    print(f"Total users with entitlement rows: {current['total_users']}")
    print(f"Users with active access: {current['active_access_users']}")
    print(f"Users with active paid access: {current['active_paid_users']}")
    print(f"At-risk users (grace/past_due/paused/canceled): {current['at_risk_users']}")
    print(f"Active paid by plan: {json.dumps(current['active_paid_by_plan'], sort_keys=True)}")
    print(f"Current statuses: {json.dumps(current['by_status'], sort_keys=True)}")
    print(
        "Recent events "
        f"({recent['window_days'] if recent['window_days'] is not None else 'all'} days): "
        f"{recent['total_events']}"
    )
    print(f"Recent event types: {json.dumps(recent['by_event_type'], sort_keys=True)}")
    print(f"Recent normalized statuses: {json.dumps(recent['normalized_status_counts'], sort_keys=True)}")
    print(f"Rough churn events in window: {recent['rough_churn_events']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
