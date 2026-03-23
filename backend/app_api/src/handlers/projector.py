from __future__ import annotations

import json
from typing import Any, Dict

import boto3

from common import config
from common.models import (
    choose_primary_subscription,
    entitlement_capabilities_for_status,
    normalize_provider,
    normalize_status,
    normalize_tier,
    free_entitlement,
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
        "product_id": normalized.get("product_id"),
        "package_name": normalized.get("package_name"),
        "base_plan_id": normalized.get("base_plan_id"),
        "offer_id": normalized.get("offer_id"),
        "source_event_id": event_record.get("event_id"),
        "source_occurred_at": occurred_at,
        "management_channel": normalized.get("management_channel") or provider,
        "updated_at": event_record.get("created_at"),
    }
    repo.upsert_subscription(subscription)

    primary_subscription = choose_primary_subscription(repo.list_subscriptions_for_user(user_id))
    if primary_subscription is None:
        current_entitlement = repo.get_entitlement(user_id)
        revision = int((current_entitlement or {}).get("revision") or 0) + 1
        repo.put_entitlement(
            free_entitlement(
                user_id=user_id,
                allow_studio_tier=config.ALLOW_STUDIO_TIER,
                revision=revision,
            ).to_dict()
        )
        return "projected_free"

    selected_provider = normalize_provider(str(primary_subscription.get("provider") or "unknown"))
    selected_tier = normalize_tier(str(primary_subscription.get("tier") or "free"))
    selected_status = normalize_status(str(primary_subscription.get("status") or "expired"))
    entitlement = {
        "user_id": user_id,
        "tier": selected_tier,
        "status": selected_status,
        "effective_at": primary_subscription.get("effective_at") or occurred_at,
        "expires_at": primary_subscription.get("expires_at"),
        "source_provider": selected_provider,
        "source_subscription_id": str(primary_subscription.get("subscription_id") or subscription_id),
        "capabilities": entitlement_capabilities_for_status(
            selected_tier,
            selected_status,
            config.ALLOW_STUDIO_TIER,
        ),
        "management_channel": primary_subscription.get("management_channel") or selected_provider,
        "source_occurred_at": primary_subscription.get("source_occurred_at") or occurred_at,
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
                        "tier": selected_tier,
                        "status": selected_status,
                        "provider": selected_provider,
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
