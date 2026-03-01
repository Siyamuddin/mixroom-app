from __future__ import annotations

import json
from typing import Any, Dict

import boto3

from common import config
from common.models import (
    default_capabilities_for_tier,
    normalize_provider,
    normalize_status,
    normalize_tier,
)
from common.repository import BillingRepository

repo = BillingRepository()
eventbridge = boto3.client("events")


def _apply_projection(event_record: Dict[str, Any]) -> str:
    user_id = str(event_record.get("user_id") or "").strip()
    normalized = event_record.get("normalized") or {}

    if not user_id:
        return "ignored_missing_user"
    if not isinstance(normalized, dict) or not normalized:
        return "ignored_missing_normalized"

    provider = normalize_provider(str(normalized.get("provider") or event_record.get("provider") or "unknown"))
    tier = normalize_tier(str(normalized.get("tier") or "free"))
    status = normalize_status(str(normalized.get("status") or "expired"))

    occurred_at = str(event_record.get("occurred_at") or event_record.get("created_at") or "")
    existing = repo.get_entitlement(user_id)
    existing_occurred = str((existing or {}).get("source_occurred_at") or "")
    if existing_occurred and occurred_at and existing_occurred > occurred_at:
        return "ignored_stale_event"

    next_revision = int((existing or {}).get("revision") or 0) + 1
    subscription_id = str(normalized.get("subscription_id") or f"{provider}:{user_id}")

    subscription = {
        "subscription_id": subscription_id,
        "user_id": user_id,
        "provider": provider,
        "tier": tier,
        "status": status,
        "effective_at": normalized.get("effective_at") or occurred_at,
        "expires_at": normalized.get("expires_at"),
        "source_event_id": event_record.get("event_id"),
        "updated_at": event_record.get("created_at"),
    }
    repo.upsert_subscription(subscription)

    entitlement = {
        "user_id": user_id,
        "tier": tier,
        "status": status,
        "effective_at": normalized.get("effective_at") or occurred_at,
        "expires_at": normalized.get("expires_at"),
        "source_provider": provider,
        "source_subscription_id": subscription_id,
        "capabilities": default_capabilities_for_tier(tier, config.ALLOW_STUDIO_TIER),
        "management_channel": normalized.get("management_channel") or provider,
        "source_occurred_at": occurred_at,
        "revision": next_revision,
    }
    repo.put_entitlement(entitlement)

    eventbridge.put_events(
        Entries=[
            {
                "Source": "mixroom.subscriptions",
                "DetailType": "entitlement.changed",
                "EventBusName": "default",
                "Detail": json.dumps(
                    {
                        "user_id": user_id,
                        "tier": tier,
                        "status": status,
                        "provider": provider,
                        "revision": next_revision,
                    }
                ),
            }
        ]
    )

    return "projected"


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    records = event.get("Records") or []

    for sqs_record in records:
        body = sqs_record.get("body") or "{}"
        payload = json.loads(body)
        event_id = str(payload.get("event_id") or "").strip()
        if not event_id:
            continue

        billing_event = repo.get_billing_event(event_id)
        if not billing_event:
            continue

        result = _apply_projection(billing_event)
        repo.mark_billing_event_processed(event_id, result)

    return {"statusCode": 200}
