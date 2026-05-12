from __future__ import annotations

import json
from typing import Any, Dict

import boto3
from common.billing_catalog import infer_plan_code
from common.collaboration_repository import CollaborationRepository
from common.models import (
    choose_primary_subscription,
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    legacy_tier_for_plan_code,
    normalize_provider,
    normalize_status,
    free_entitlement,
    status_has_active_access,
    subscription_effective_status,
)
from common.repository import BillingRepository

repo = BillingRepository()
collaboration_repo = CollaborationRepository()
eventbridge = boto3.client("events")
_TEAM_PLAN_CODES = {"studio", "enterprise", "education"}


def _is_team_plan(raw: Dict[str, Any]) -> bool:
    plan_code = infer_plan_code(raw.get("plan_code") or raw.get("tier") or "")
    return plan_code in _TEAM_PLAN_CODES


def _personal_subscriptions(subscriptions: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return [item for item in subscriptions if not _is_team_plan(item)]


def _sync_team_organization(subscription: Dict[str, Any]) -> None:
    plan_code = str(subscription.get("plan_code") or subscription.get("tier") or "").strip().lower()
    if plan_code not in {"studio", "enterprise", "education"}:
        return
    try:
        collaboration_repo.sync_organization_for_subscription(subscription)
    except Exception:
        return


def _apply_projection(event_record: Dict[str, Any]) -> str:
    user_id = str(event_record.get("user_id") or "").strip()
    normalized = event_record.get("normalized") or {}

    if not user_id:
        return "ignored_missing_user"
    if not isinstance(normalized, dict) or not normalized:
        return "ignored_missing_normalized"

    provider = normalize_provider(str(normalized.get("provider") or event_record.get("provider") or "unknown"))
    status = normalize_status(str(normalized.get("status") or "expired"))
    plan_code = infer_plan_code(normalized.get("plan_code") or normalized.get("tier") or "")

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
        "tier": legacy_tier_for_plan_code(plan_code),
        "plan_code": plan_code,
        "status": status,
        "effective_at": normalized.get("effective_at") or occurred_at,
        "expires_at": normalized.get("expires_at"),
        "product_id": normalized.get("product_id"),
        "product_code": normalized.get("product_code"),
        "package_name": normalized.get("package_name"),
        "base_plan_id": normalized.get("base_plan_id"),
        "offer_id": normalized.get("offer_id"),
        "source_event_id": event_record.get("event_id"),
        "source_occurred_at": occurred_at,
        "management_channel": normalized.get("management_channel") or provider,
        "updated_at": event_record.get("created_at"),
    }
    repo.upsert_subscription(subscription)
    _sync_team_organization(subscription)

    subscriptions = [
        item
        for item in repo.list_subscriptions_for_user(user_id)
        if isinstance(item, dict)
        and str(item.get("subscription_id") or "") != subscription_id
    ]
    subscriptions.append(subscription)
    primary_subscription = choose_primary_subscription(
        _personal_subscriptions(subscriptions)
    )
    if primary_subscription is None:
        current_entitlement = repo.get_entitlement(user_id)
        revision = int((current_entitlement or {}).get("revision") or 0) + 1
        repo.put_entitlement(
            free_entitlement(
                user_id=user_id,
                revision=revision,
            ).to_dict()
        )
        return "projected_free"

    selected_provider = normalize_provider(str(primary_subscription.get("provider") or "unknown"))
    selected_status = subscription_effective_status(primary_subscription)
    selected_plan_code = infer_plan_code(
        primary_subscription.get("plan_code") or primary_subscription.get("tier") or ""
    )
    entitlement = {
        "user_id": user_id,
        "tier": legacy_tier_for_plan_code(selected_plan_code),
        "status": selected_status,
        "effective_at": primary_subscription.get("effective_at") or occurred_at,
        "expires_at": primary_subscription.get("expires_at"),
        "source_provider": selected_provider,
        "source_subscription_id": str(primary_subscription.get("subscription_id") or subscription_id),
        "capabilities": entitlement_capabilities_for_status(
            selected_plan_code,
            selected_status,
        ),
        "limits": entitlement_limits_for_status(
            selected_plan_code,
            selected_status,
        ),
        "management_channel": primary_subscription.get("management_channel") or selected_provider,
        "plan_code": selected_plan_code,
        "product_code": primary_subscription.get("product_code"),
        "source_occurred_at": primary_subscription.get("source_occurred_at") or occurred_at,
        "revision": next_revision,
    }
    repo.put_entitlement(entitlement)
    _expire_reclaimed_prior_entitlement(
        normalized=normalized,
        provider=provider,
        subscription_id=subscription_id,
    )

    eventbridge.put_events(
        Entries=[
            {
                "Source": "mixroom.subscriptions",
                "DetailType": "entitlement.changed",
                "EventBusName": "default",
                "Detail": json.dumps(
                    {
                        "user_id": user_id,
                        "plan_code": selected_plan_code,
                        "status": selected_status,
                        "provider": selected_provider,
                        "revision": next_revision,
                    }
                ),
            }
        ]
    )

    return "projected"


def _expire_reclaimed_prior_entitlement(
    *,
    normalized: Dict[str, Any],
    provider: str,
    subscription_id: str,
) -> None:
    reclaimed_from_user_id = str(
        normalized.get("reclaimed_from_user_id") or ""
    ).strip()
    if not reclaimed_from_user_id or not subscription_id:
        return

    prior = repo.get_entitlement(reclaimed_from_user_id)
    if not isinstance(prior, dict):
        return
    if str(prior.get("source_provider") or "").strip().lower() != provider:
        return
    if str(prior.get("source_subscription_id") or "").strip() != subscription_id:
        return
    if status_has_active_access(subscription_effective_status(prior)):
        return

    revision = int(prior.get("revision") or 0) + 1
    repo.put_entitlement(
        free_entitlement(
            user_id=reclaimed_from_user_id,
            revision=revision,
        ).to_dict()
    )


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
