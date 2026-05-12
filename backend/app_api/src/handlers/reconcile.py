from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
import uuid

from common.models import (
    choose_primary_subscription,
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    free_entitlement,
    legacy_tier_for_plan_code,
    normalize_plan_code,
    normalize_provider,
    normalize_status,
    status_has_active_access,
    subscription_effective_status,
)
from common.collaboration_repository import CollaborationRepository
from common.monitoring import capture_exception, init_sentry
from common.repository import BillingRepository

repo = BillingRepository()
collaboration_repo = CollaborationRepository()
init_sentry("mixroom-app-api-reconcile")

_MOBILE_STORE_PROVIDERS = {"apple", "google"}
_MOBILE_STORE_EXPIRY_RECONCILE_GRACE = timedelta(minutes=15)
_TEAM_PLAN_CODES = {"studio", "enterprise", "education"}


def _is_team_plan(raw: Dict[str, Any]) -> bool:
    plan_code = normalize_plan_code(
        raw.get("plan_code")
        or raw.get("tier")
        or "free"
    )
    return plan_code in _TEAM_PLAN_CODES


def _personal_subscriptions(subscriptions: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return [item for item in subscriptions if not _is_team_plan(item)]


def _sync_team_organization(subscription: Dict[str, Any]) -> None:
    plan_code = str(subscription.get("plan_code") or subscription.get("tier") or "").strip().lower()
    if plan_code not in {"studio", "enterprise", "education"}:
        return
    try:
        collaboration_repo.sync_organization_for_subscription(subscription)
    except Exception as exc:
        capture_exception(
            exc,
            tags={
                "service": "subscriptions_reconcile",
                "operation": "sync_team_organization",
                "plan_code": plan_code,
            },
            context={
                "subscription_id": subscription.get("subscription_id"),
                "user_id": subscription.get("user_id"),
                "status": subscription.get("status"),
            },
        )
        return


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

    if hasattr(repo, "list_expired_subscriptions_for_statuses"):
        subscription_iterable = repo.list_expired_subscriptions_for_statuses(
            statuses=("active", "trialing", "grace_period"),
            expires_before=now.isoformat(),
        )
    else:
        subscription_iterable = repo.scan_subscriptions()

    for sub in subscription_iterable:
        scanned += 1
        user_id = str(sub.get("user_id") or "").strip()
        sub_id = str(sub.get("subscription_id") or "").strip()
        if not user_id or not sub_id:
            continue

        expires_at = _parse_ts(sub.get("expires_at"))
        if not expires_at or expires_at > now:
            continue
        provider = normalize_provider(str(sub.get("provider") or "unknown"))
        if (
            provider in _MOBILE_STORE_PROVIDERS
            and expires_at + _MOBILE_STORE_EXPIRY_RECONCILE_GRACE > now
        ):
            continue

        status = str(sub.get("status") or "").lower()
        if status in {"expired", "refunded", "revoked"}:
            continue

        updated_sub = dict(sub)
        updated_sub["status"] = "expired"
        repo.upsert_subscription(updated_sub)
        _sync_team_organization(updated_sub)

        current_ent = repo.get_entitlement(user_id)
        if not current_ent:
            continue

        if str(current_ent.get("source_subscription_id") or "") != sub_id:
            continue

        revision = int(current_ent.get("revision") or 0) + 1
        primary_subscription = choose_primary_subscription(
            _personal_subscriptions(repo.list_subscriptions_for_user(user_id))
        )
        if primary_subscription and status_has_active_access(
            subscription_effective_status(primary_subscription)
        ):
            selected_status = subscription_effective_status(primary_subscription)
            selected_plan_code = normalize_plan_code(
                primary_subscription.get("plan_code")
                or primary_subscription.get("tier")
                or "free"
            )
            repo.put_entitlement(
                {
                    "user_id": user_id,
                    "tier": legacy_tier_for_plan_code(selected_plan_code),
                    "status": selected_status,
                    "effective_at": primary_subscription.get("effective_at"),
                    "expires_at": primary_subscription.get("expires_at"),
                    "source_provider": normalize_provider(
                        str(primary_subscription.get("provider") or "unknown")
                    ),
                    "source_subscription_id": str(
                        primary_subscription.get("subscription_id") or ""
                    ),
                    "capabilities": entitlement_capabilities_for_status(
                        selected_plan_code,
                        selected_status,
                    ),
                    "limits": entitlement_limits_for_status(
                        selected_plan_code,
                        selected_status,
                    ),
                    "management_channel": primary_subscription.get("management_channel")
                    or primary_subscription.get("provider")
                    or "unknown",
                    "plan_code": selected_plan_code,
                    "product_code": primary_subscription.get("product_code"),
                    "source_occurred_at": primary_subscription.get("source_occurred_at"),
                    "revision": revision,
                }
            )
        else:
            free = free_entitlement(
                user_id=user_id,
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
