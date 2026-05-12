from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional

from .billing_catalog import (
    catalog_plan_by_code,
    catalog_product_by_code,
    infer_plan_code,
)
from .models import status_has_active_access, subscription_effective_status, normalize_status
from .repository import BillingRepository


class ProviderVerificationError(Exception):
    def __init__(self, message: str, *, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().isoformat()


def parse_datetime(raw: Any) -> Optional[datetime]:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw.astimezone(timezone.utc)

    text = str(raw).strip()
    if not text:
        return None

    if text.isdigit():
        millis = int(text)
        if millis > 9999999999:
            return datetime.fromtimestamp(millis / 1000.0, tz=timezone.utc)
        return datetime.fromtimestamp(millis, tz=timezone.utc)

    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def datetime_to_iso(raw: Any) -> Optional[str]:
    parsed = parse_datetime(raw)
    return parsed.isoformat() if parsed else None


def first_present(*values: Any) -> Optional[Any]:
    for value in values:
        if value is None:
            continue
        if isinstance(value, str) and not value.strip():
            continue
        return value
    return None


def resolve_access_for_product(
    repo: BillingRepository,
    provider: str,
    product_id: str,
    *,
    fallback_plan_code: str = "",
) -> Dict[str, str]:
    mapping = repo.get_catalog_mapping(provider, product_id)
    if mapping:
        raw_plan_code = str(
            mapping.get("plan_code") or fallback_plan_code or ""
        ).strip().lower()
        plan_code = raw_plan_code or infer_plan_code("")
        return {
            "plan_code": plan_code,
            "product_code": str(mapping.get("product_code") or "").strip().lower(),
        }

    catalog_match = _catalog_access_for_product(provider, product_id)
    if catalog_match:
        return catalog_match

    fallback_plan = str(fallback_plan_code or "").strip().lower()
    return {
        "plan_code": infer_plan_code(fallback_plan) if fallback_plan else _infer_plan_code_from_product_id(product_id),
        "product_code": "",
    }


def _catalog_access_for_product(provider: str, product_id: str) -> Optional[Dict[str, str]]:
    normalized_provider = str(provider or "").strip().lower()
    normalized_product_id = str(product_id or "").strip()
    if not normalized_provider or not normalized_product_id:
        return None

    try:
        from .billing_catalog_repository import BillingCatalogRepository

        catalog = BillingCatalogRepository().get_catalog()
    except Exception:
        return None

    for provider_product in (
        catalog.get("provider_products") or catalog.get("offers") or []
    ):
        if not isinstance(provider_product, dict):
            continue
        if str(provider_product.get("provider") or "").strip().lower() != normalized_provider:
            continue
        if str(provider_product.get("provider_product_id") or "").strip() != normalized_product_id:
            continue
        if not bool(provider_product.get("enabled", True)):
            raise ProviderVerificationError(
                f"{provider} product is disabled in the billing catalog.",
                status_code=409,
            )
        product_code = str(provider_product.get("product_code") or "").strip().lower()
        product = catalog_product_by_code(product_code, catalog=catalog)
        if not product or not bool(product.get("enabled", True)):
            raise ProviderVerificationError(
                f"{provider} product is disabled in the billing catalog.",
                status_code=409,
            )
        plan_code = str(product.get("plan_code") or "").strip().lower()
        plan = catalog_plan_by_code(plan_code, catalog=catalog)
        resolved_plan_code = str(plan.get("code") or plan_code or "").strip().lower()
        return {
            "plan_code": resolved_plan_code or infer_plan_code(plan_code),
            "product_code": product_code,
        }
    return None


def _infer_plan_code_from_product_id(product_id: str) -> str:
    value = str(product_id or "").strip().lower()
    if "education" in value:
        return "education"
    if "enterprise" in value:
        return "enterprise"
    if "studio" in value:
        return "studio"
    if "starter" in value:
        return "starter"
    if "producer" in value or "_pro_" in value or value.endswith("_pro"):
        return "producer"
    return "free"


def assert_user_link_available(
    *,
    resolved_user_id: str,
    expected_user_id: str = "",
    existing_link_user_id: str = "",
    provider: str,
) -> str:
    if expected_user_id and resolved_user_id and expected_user_id != resolved_user_id:
        raise ProviderVerificationError(
            f"{provider} purchase belongs to a different Mixroom account.",
            status_code=409,
        )
    if expected_user_id and existing_link_user_id and expected_user_id != existing_link_user_id:
        raise ProviderVerificationError(
            f"{provider} purchase is already linked to another Mixroom account.",
            status_code=409,
        )

    user_id = resolved_user_id or existing_link_user_id or expected_user_id
    if not user_id:
        raise ProviderVerificationError(
            f"Unable to resolve Mixroom user for {provider} purchase.",
            status_code=409,
        )
    return user_id


def resolve_purchase_user_link(
    repo: BillingRepository,
    *,
    resolved_user_id: str,
    expected_user_id: str = "",
    existing_link_user_id: str = "",
    provider: str,
    subscription_id: str = "",
    allow_active_reclaim: bool = False,
) -> tuple[str, str]:
    if expected_user_id and resolved_user_id and expected_user_id != resolved_user_id:
        raise ProviderVerificationError(
            f"{provider} purchase belongs to a different Mixroom account.",
            status_code=409,
        )

    if expected_user_id and existing_link_user_id and expected_user_id != existing_link_user_id:
        can_reclaim = (
            resolved_user_id == expected_user_id
            and (
                allow_active_reclaim
                or _linked_store_subscription_is_inactive(
                    repo,
                    provider=provider,
                    linked_user_id=existing_link_user_id,
                    subscription_id=subscription_id,
                )
            )
        )
        if can_reclaim:
            return expected_user_id, existing_link_user_id
        raise ProviderVerificationError(
            f"{provider} purchase is already linked to another Mixroom account.",
            status_code=409,
        )

    user_id = resolved_user_id or existing_link_user_id or expected_user_id
    if not user_id:
        raise ProviderVerificationError(
            f"Unable to resolve Mixroom user for {provider} purchase.",
            status_code=409,
        )
    return user_id, ""


def _linked_store_subscription_is_inactive(
    repo: BillingRepository,
    *,
    provider: str,
    linked_user_id: str,
    subscription_id: str,
) -> bool:
    if not linked_user_id or not subscription_id:
        return False

    normalized_provider = _store_provider_key(provider)
    entitlement = repo.get_entitlement(linked_user_id) or {}
    entitlement_matches = (
        str(entitlement.get("source_provider") or "").strip().lower()
        == normalized_provider
        and str(entitlement.get("source_subscription_id") or "").strip()
        == subscription_id
    )
    if entitlement_matches and status_has_active_access(
        subscription_effective_status(entitlement)
    ):
        return False

    matching_subscription_count = 0
    for subscription in repo.list_subscriptions_for_user(linked_user_id):
        if not isinstance(subscription, dict):
            continue
        if (
            str(subscription.get("provider") or "").strip().lower()
            != normalized_provider
        ):
            continue
        if str(subscription.get("subscription_id") or "").strip() != subscription_id:
            continue
        matching_subscription_count += 1
        if status_has_active_access(subscription_effective_status(subscription)):
            return False

    return entitlement_matches or matching_subscription_count > 0


def _store_provider_key(provider: str) -> str:
    value = str(provider or "").strip().lower()
    if value.startswith("google"):
        return "google"
    if value.startswith("apple"):
        return "apple"
    return value


def active_status_for_expiry(
    *,
    expires_at: Any,
    revoked_at: Any = None,
    refund: bool = False,
    active_status: str = "active",
) -> str:
    if revoked_at:
        return "refunded" if refund else "revoked"

    expires_dt = parse_datetime(expires_at)
    if expires_dt is None:
        return normalize_status(active_status)
    if expires_dt > utc_now():
        return normalize_status(active_status)
    return "expired"


def maybe_link_customer(
    repo: BillingRepository,
    *,
    provider: str,
    customer_key: str,
    user_id: str,
    attributes: Optional[Dict[str, Any]] = None,
) -> None:
    if not customer_key:
        return
    repo.put_customer_link(provider, customer_key, user_id, attributes)


def maybe_link_purchase_token(
    repo: BillingRepository,
    *,
    provider: str,
    token: str,
    attributes: Optional[Dict[str, Any]] = None,
) -> None:
    if not token:
        return
    repo.put_purchase_token(provider, token, attributes)
