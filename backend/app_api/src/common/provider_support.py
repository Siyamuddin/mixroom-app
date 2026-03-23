from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional

from .models import infer_tier_from_product_id, normalize_status, normalize_tier
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


def resolve_tier_for_product(
    repo: BillingRepository,
    provider: str,
    product_id: str,
    *,
    fallback_tier: str = "",
) -> str:
    mapping = repo.get_catalog_mapping(provider, product_id)
    if mapping:
        tier = normalize_tier(str(mapping.get("tier") or ""))
        if tier != "free":
            return tier

    normalized_fallback = normalize_tier(fallback_tier)
    if normalized_fallback != "free":
        return normalized_fallback

    return infer_tier_from_product_id(product_id)


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
