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
_ORG_ONLY_PLAN_CODES = {"enterprise", "education"}
_PADDLE_PROJECTABLE_TRANSACTION_EVENTS = {
    "transaction.canceled",
    "transaction.completed",
    "transaction.payment_failed",
    "transaction.refunded",
}
_PURCHASE_SUCCESS_EVENT_TYPES = {
    "toss_payment_confirmed",
    "toss_billing_payment_approved",
    "transaction.completed",
}
_APPLE_PURCHASE_SUCCESS_TYPES = {"SUBSCRIBED", "DID_RENEW"}
# Google RTDN subscriptionNotification values: SUBSCRIPTION_RECOVERED,
# SUBSCRIPTION_RENEWED, and SUBSCRIPTION_PURCHASED.  A recovery is excluded:
# it does not represent a new successful charge.
_GOOGLE_PURCHASE_SUCCESS_TYPES = {2, 4}


def _is_team_plan(raw: Dict[str, Any]) -> bool:
    plan_code = infer_plan_code(raw.get("plan_code") or raw.get("tier") or "")
    return plan_code in _ORG_ONLY_PLAN_CODES


def _personal_subscriptions(subscriptions: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return [item for item in subscriptions if not _is_team_plan(item)]


def _is_projectable_event(event_record: Dict[str, Any], provider: str, normalized: Dict[str, Any]) -> bool:
    if provider != "paddle":
        return True
    event_type = str(event_record.get("event_type") or "").strip().lower()
    if not event_type:
        return True
    if event_type.startswith("subscription."):
        return True
    if event_type in _PADDLE_PROJECTABLE_TRANSACTION_EVENTS:
        return str(normalized.get("subscription_id") or "").strip().startswith("sub_")
    return False


def _is_successful_purchase(event_record: Dict[str, Any], provider: str, normalized: Dict[str, Any]) -> bool:
    """Return true only for a completed charge, never entitlement state changes."""
    if str(normalized.get("status") or "").strip().lower() not in {"active", "trialing"}:
        return False
    event_type = str(event_record.get("event_type") or "").strip().lower()
    if event_type in _PURCHASE_SUCCESS_EVENT_TYPES:
        return True

    raw = event_record.get("raw_payload") or {}
    if not isinstance(raw, dict):
        return False
    if provider == "apple" and event_type == "apple_webhook":
        return str(raw.get("notificationType") or "").strip().upper() in _APPLE_PURCHASE_SUCCESS_TYPES
    if provider == "google" and event_type == "google_rtdn":
        notification = raw.get("subscriptionNotification") or {}
        if not isinstance(notification, dict):
            return False
        try:
            return int(notification.get("notificationType")) in _GOOGLE_PURCHASE_SUCCESS_TYPES
        except (TypeError, ValueError):
            return False
    return False


def _purchase_money(event_record: Dict[str, Any], normalized: Dict[str, Any]) -> Dict[str, Any]:
    """Expose provider-reported money when available; never invent an amount."""
    amount = normalized.get("billing_amount")
    currency = normalized.get("billing_currency")
    raw = event_record.get("raw_payload") or {}
    if isinstance(raw, dict) and not amount:
        data = raw.get("data") if isinstance(raw.get("data"), dict) else raw
        details = data.get("details") if isinstance(data.get("details"), dict) else {}
        totals = details.get("totals") if isinstance(details.get("totals"), dict) else {}
        amount = totals.get("total") or data.get("amount") or data.get("price")
        currency = currency or totals.get("currency_code") or data.get("currency")
    result: Dict[str, Any] = {}
    if amount not in (None, ""):
        result["amount"] = amount
    if currency:
        result["currency"] = str(currency).upper()
    return result


def _value_or_existing(normalized: Dict[str, Any], existing: Dict[str, Any] | None, key: str) -> Any:
    value = normalized.get(key)
    if value is not None and str(value).strip() != "":
        return value
    if isinstance(existing, dict):
        return existing.get(key)
    return value


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
    if not _is_projectable_event(event_record, provider, normalized):
        return "ignored_non_subscription_event"
    status = normalize_status(str(normalized.get("status") or "expired"))
    plan_code = infer_plan_code(normalized.get("plan_code") or normalized.get("tier") or "")

    occurred_at = str(event_record.get("occurred_at") or event_record.get("created_at") or "")
    subscription_id = str(normalized.get("subscription_id") or f"{provider}:{user_id}")
    existing_subscription = repo.get_subscription(subscription_id)
    existing_subscription_occurred = str((existing_subscription or {}).get("source_occurred_at") or "")
    if existing_subscription_occurred and occurred_at and existing_subscription_occurred > occurred_at:
        return "ignored_stale_event"

    existing = repo.get_entitlement(user_id)
    next_revision = int((existing or {}).get("revision") or 0) + 1

    subscription = {
        "subscription_id": subscription_id,
        "user_id": user_id,
        "provider": provider,
        "customer_id": normalized.get("customer_id"),
        "customer_email": normalized.get("customer_email"),
        "payment_method": normalized.get("payment_method"),
        "tier": legacy_tier_for_plan_code(plan_code),
        "plan_code": plan_code,
        "status": status,
        "effective_at": _value_or_existing(normalized, existing_subscription, "effective_at") or occurred_at,
        "expires_at": _value_or_existing(normalized, existing_subscription, "expires_at"),
        "product_id": _value_or_existing(normalized, existing_subscription, "product_id"),
        "product_code": _value_or_existing(normalized, existing_subscription, "product_code"),
        "package_name": _value_or_existing(normalized, existing_subscription, "package_name"),
        "base_plan_id": _value_or_existing(normalized, existing_subscription, "base_plan_id"),
        "offer_id": _value_or_existing(normalized, existing_subscription, "offer_id"),
        "next_billed_at": _value_or_existing(normalized, existing_subscription, "next_billed_at"),
        "seat_count": _value_or_existing(normalized, existing_subscription, "seat_count"),
        "extra_storage_tb": _value_or_existing(normalized, existing_subscription, "extra_storage_tb"),
        "billing_key_parameter_name": _value_or_existing(
            normalized,
            existing_subscription,
            "billing_key_parameter_name",
        ),
        "billing_key_secret_arn": _value_or_existing(normalized, existing_subscription, "billing_key_secret_arn"),
        "billing_amount": _value_or_existing(normalized, existing_subscription, "billing_amount"),
        "billing_currency": _value_or_existing(normalized, existing_subscription, "billing_currency"),
        "cancel_at_period_end": bool(normalized.get("cancel_at_period_end") or False),
        "source_event_id": event_record.get("event_id"),
        "source_occurred_at": occurred_at,
        "management_channel": normalized.get("management_channel") or provider,
        "updated_at": event_record.get("created_at"),
    }
    repo.upsert_subscription(subscription)
    _sync_team_organization(subscription)

    existing_occurred = str((existing or {}).get("source_occurred_at") or "")
    existing_subscription_id = str((existing or {}).get("source_subscription_id") or "").strip()
    if (
        existing_subscription_id
        and existing_subscription_id != subscription_id
        and existing_occurred
        and occurred_at
        and existing_occurred > occurred_at
    ):
        return "projected_subscription_only"

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
    limit_overrides = _limit_overrides_for_subscription(primary_subscription)
    entitlement = {
        "user_id": user_id,
        "tier": legacy_tier_for_plan_code(selected_plan_code),
        "status": selected_status,
        "effective_at": primary_subscription.get("effective_at") or occurred_at,
        "expires_at": primary_subscription.get("expires_at"),
        "source_provider": selected_provider,
        "source_subscription_id": str(primary_subscription.get("subscription_id") or subscription_id),
        "source_customer_id": primary_subscription.get("customer_id"),
        "billing_email": primary_subscription.get("customer_email"),
        "payment_method": primary_subscription.get("payment_method"),
        "capabilities": entitlement_capabilities_for_status(
            selected_plan_code,
            selected_status,
        ),
        "limits": entitlement_limits_for_status(
            selected_plan_code,
            selected_status,
        ),
        "limit_overrides": limit_overrides,
        "limits_are_overrides": bool(limit_overrides),
        "management_channel": primary_subscription.get("management_channel") or selected_provider,
        "plan_code": selected_plan_code,
        "product_code": primary_subscription.get("product_code"),
        "next_billed_at": primary_subscription.get("next_billed_at"),
        "seat_count": primary_subscription.get("seat_count"),
        "extra_storage_tb": primary_subscription.get("extra_storage_tb"),
        "cancel_at_period_end": bool(primary_subscription.get("cancel_at_period_end") or False),
        "source_occurred_at": primary_subscription.get("source_occurred_at") or occurred_at,
        "revision": next_revision,
    }
    repo.put_entitlement(entitlement)
    _expire_reclaimed_prior_entitlement(
        normalized=normalized,
        provider=provider,
        subscription_id=subscription_id,
    )

    event_details = {
        "user_id": user_id,
        "plan_code": selected_plan_code,
        "status": selected_status,
        "provider": selected_provider,
        "revision": next_revision,
    }
    entries = [
        {
            "Source": "mixroom.subscriptions",
            "DetailType": "entitlement.changed",
            "EventBusName": "default",
            "Detail": json.dumps(event_details),
        }
    ]
    if _is_successful_purchase(event_record, provider, normalized):
        purchase = {
            **event_details,
            "event_id": str(event_record.get("event_id") or ""),
            "product_code": str(subscription.get("product_code") or ""),
            "customer_email": str(subscription.get("customer_email") or ""),
            "purchased_at": occurred_at,
            **_purchase_money(event_record, normalized),
        }
        entries.append(
            {
                "Source": "mixroom.subscriptions",
                "DetailType": "billing.purchase_completed",
                "EventBusName": "default",
                "Detail": json.dumps(purchase),
            }
        )
    eventbridge.put_events(Entries=entries)

    return "projected"


def _limit_overrides_for_subscription(subscription: Dict[str, Any]) -> Dict[str, Any]:
    overrides: Dict[str, Any] = {}
    try:
        seat_count = int(subscription.get("seat_count") or 0)
    except (TypeError, ValueError):
        seat_count = 0
    if seat_count > 0:
        overrides["members"] = seat_count

    try:
        extra_storage_tb = int(subscription.get("extra_storage_tb") or 0)
    except (TypeError, ValueError):
        extra_storage_tb = 0
    if extra_storage_tb > 0:
        overrides["shared_storage_gb"] = 1024 + (extra_storage_tb * 1024)
    return overrides


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
        if billing_event.get("processed_at"):
            continue

        result = _apply_projection(billing_event)
        repo.mark_billing_event_processed(event_id, result)

    return {"statusCode": 200}
