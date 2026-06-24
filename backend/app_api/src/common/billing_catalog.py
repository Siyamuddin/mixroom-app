from __future__ import annotations

from copy import deepcopy
import re
from typing import Any, Dict, Iterable

from .models import normalize_plan_code, normalize_provider
from .plan_catalog import (
    default_plan_definitions,
    default_product_definitions,
    default_provider_product_definitions,
    default_support_settings,
)

_CODE_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
_URL_RE = re.compile(r"^https?://", re.IGNORECASE)
_ALLOWED_PLAN_GROUPS = frozenset(
    {"individual", "team", "enterprise", "education", "credits", "pass"}
)
_ALLOWED_PRODUCT_TYPES = frozenset(
    {"subscription", "credits", "day_pass", "contract"}
)
_ALLOWED_INTERVALS = frozenset(
    {"monthly", "yearly", "one_time", "daily", "custom"}
)


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_bool(value: Any, *, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    normalized = _safe_str(value).lower()
    if normalized in {"true", "1", "yes", "y", "on"}:
        return True
    if normalized in {"false", "0", "no", "n", "off"}:
        return False
    return default


def _safe_int(value: Any, *, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _safe_float(value: Any, *, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _validate_code(value: Any, *, field_name: str) -> str:
    normalized = _safe_str(value).lower()
    if not normalized:
        raise ValueError(f"{field_name} is required.")
    if not _CODE_RE.match(normalized):
        raise ValueError(
            f"{field_name} must contain only lowercase letters, digits, hyphens, or underscores."
        )
    return normalized


def _normalize_url(value: Any) -> str:
    normalized = _safe_str(value)
    if not normalized:
        return ""
    if not _URL_RE.match(normalized):
        raise ValueError("Support and management URLs must start with http:// or https://.")
    return normalized


def _normalize_string_map(
    raw: Any,
    *,
    value_max_length: int = 200,
) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    result: Dict[str, Any] = {}
    for key, value in raw.items():
        normalized_key = _validate_code(key, field_name="Map key")
        if isinstance(value, bool):
            result[normalized_key] = value
            continue
        if isinstance(value, (int, float)):
            result[normalized_key] = value
            continue
        normalized_value = _safe_str(value)
        if not normalized_value:
            continue
        if len(normalized_value) > value_max_length:
            raise ValueError(
                f"Value for {normalized_key} must be {value_max_length} characters or less."
            )
        result[normalized_key] = normalized_value
    return result


def merge_capabilities(*maps: Dict[str, Any]) -> Dict[str, bool]:
    result: Dict[str, bool] = {}
    for current in maps:
        if not isinstance(current, dict):
            continue
        for key, value in current.items():
            normalized_key = _safe_str(key)
            if not normalized_key:
                continue
            result[normalized_key] = result.get(normalized_key, False) or bool(value)
    return result


def merge_limits(*maps: Dict[str, Any]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for current in maps:
        if not isinstance(current, dict):
            continue
        for key, value in current.items():
            normalized_key = _safe_str(key)
            if not normalized_key or value in (None, ""):
                continue
            if isinstance(value, bool):
                result[normalized_key] = bool(result.get(normalized_key)) or value
                continue
            if isinstance(value, (int, float)):
                existing = result.get(normalized_key)
                if str(existing or "").strip().lower() in {"custom", "unlimited"}:
                    continue
                if isinstance(existing, (int, float)):
                    result[normalized_key] = max(existing, value)
                else:
                    result[normalized_key] = value
                continue
            normalized_value = _safe_str(value)
            if not normalized_value:
                continue
            if normalized_value.lower() in {"custom", "unlimited"}:
                result[normalized_key] = normalized_value
                continue
            existing = result.get(normalized_key)
            if existing in (None, ""):
                result[normalized_key] = normalized_value
    return result


def infer_plan_code(
    raw_plan_code: Any,
    *,
    known_plan_codes: set[str] | None = None,
) -> str:
    normalized_plan_code = normalize_plan_code(raw_plan_code)
    if normalized_plan_code in default_plan_codes() or (
        known_plan_codes and normalized_plan_code in known_plan_codes
    ):
        return normalized_plan_code
    return "free"


def default_plan_codes() -> set[str]:
    return {
        _safe_str(item.get("code")).lower()
        for item in default_plan_definitions()
        if _safe_str(item.get("code"))
    }


def default_catalog() -> Dict[str, Any]:
    return {
        "plans": sort_plans(default_plan_definitions()),
        "products": sort_products(default_product_definitions()),
        "provider_products": sort_provider_products(default_provider_product_definitions()),
        "support": default_support_settings(),
    }


def sort_plans(plans: Iterable[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return sorted(
        [deepcopy(item) for item in plans if isinstance(item, dict)],
        key=lambda item: (
            _safe_int(item.get("rank"), default=999),
            _safe_str(item.get("label") or item.get("code")),
        ),
    )


def sort_products(products: Iterable[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return sorted(
        [deepcopy(item) for item in products if isinstance(item, dict)],
        key=lambda item: (
            _safe_str(item.get("plan_code")),
            _safe_int(item.get("rank"), default=999),
            _safe_str(item.get("label") or item.get("code")),
        ),
    )


def sort_provider_products(provider_products: Iterable[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return sorted(
        [deepcopy(item) for item in provider_products if isinstance(item, dict)],
        key=lambda item: (
            _safe_str(item.get("provider")),
            _safe_str(item.get("product_code")),
            _safe_str(item.get("provider_product_id")),
        ),
    )


def catalog_plan_by_code(
    plan_code: str,
    *,
    catalog: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    plans = (catalog or default_catalog()).get("plans") or []
    normalized_plan_code = _safe_str(plan_code).lower()
    for plan in plans:
        if _safe_str(plan.get("code")).lower() == normalized_plan_code:
            return deepcopy(plan)

    resolved = infer_plan_code(plan_code)
    for plan in plans:
        if _safe_str(plan.get("code")).lower() == resolved:
            return deepcopy(plan)
    for plan in default_plan_definitions():
        if _safe_str(plan.get("code")).lower() == resolved:
            return deepcopy(plan)
    return deepcopy(default_plan_definitions()[0])


def catalog_product_by_code(
    product_code: str,
    *,
    catalog: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    normalized = _safe_str(product_code).lower()
    products = (catalog or default_catalog()).get("products") or []
    for product in products:
        if _safe_str(product.get("code")).lower() == normalized:
            return deepcopy(product)
    return {}


def normalize_plan_definition(raw: Any) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError("Each billing plan must be an object.")
    code = _validate_code(raw.get("code"), field_name="Plan code")
    group = _safe_str(raw.get("group") or "individual").lower() or "individual"
    if group not in _ALLOWED_PLAN_GROUPS:
        raise ValueError("Plan group is invalid.")
    label = _safe_str(raw.get("label")) or code.replace("_", " ").title()
    description = _safe_str(raw.get("description"))
    return {
        "code": code,
        "label": label,
        "group": group,
        "rank": _safe_int(raw.get("rank"), default=999),
        "active": _safe_bool(raw.get("active"), default=True),
        "description": description,
        "capabilities": {
            key: bool(value)
            for key, value in _normalize_string_map(raw.get("capabilities")).items()
        },
        "limits": _normalize_string_map(raw.get("limits")),
    }


def normalize_product_definition(raw: Any, *, known_plan_codes: set[str]) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError("Each billing product must be an object.")
    code = _validate_code(raw.get("code"), field_name="Product code")
    plan_code = (
        _validate_code(raw.get("plan_code"), field_name=f"Plan code for product {code}")
        if _safe_str(raw.get("plan_code"))
        else "free"
    )
    if plan_code not in known_plan_codes:
        raise ValueError(f"Unknown plan_code for product {code}.")
    product_type = _safe_str(raw.get("type") or "subscription").lower()
    if product_type not in _ALLOWED_PRODUCT_TYPES:
        raise ValueError("Billing product type is invalid.")
    billing_interval = _safe_str(raw.get("billing_interval") or "monthly").lower()
    if billing_interval not in _ALLOWED_INTERVALS:
        raise ValueError("Billing interval is invalid.")
    platforms = []
    for value in raw.get("platforms") or []:
        normalized = _safe_str(value).lower()
        if normalized and normalized not in platforms:
            platforms.append(normalized)
    return {
        "code": code,
        "plan_code": plan_code,
        "type": product_type,
        "billing_interval": billing_interval,
        "label": _safe_str(raw.get("label")) or code.replace("_", " ").title(),
        "description": _safe_str(raw.get("description")),
        "enabled": _safe_bool(raw.get("enabled"), default=True),
        "management_channel": _safe_str(raw.get("management_channel") or "web"),
        "platforms": platforms,
        "price_display": _safe_str(raw.get("price_display")),
        "price_krw": _safe_int(raw.get("price_krw"), default=0),
        "trial_days": _safe_int(raw.get("trial_days"), default=0),
        "rank": _safe_int(raw.get("rank"), default=999),
    }


def normalize_provider_product_definition(raw: Any, *, known_product_codes: set[str]) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError("Each provider product must be an object.")
    code = _validate_code(raw.get("code"), field_name="Provider product code")
    provider = normalize_provider(raw.get("provider"))
    if provider == "unknown":
        raise ValueError("Provider product provider is invalid.")
    product_code = _validate_code(raw.get("product_code"), field_name="Provider product product_code")
    if product_code not in known_product_codes:
        raise ValueError(f"Unknown product_code for provider product {code}.")
    provider_product_id = _safe_str(raw.get("provider_product_id"))
    if not provider_product_id:
        raise ValueError("Provider product provider_product_id is required.")
    return {
        "code": code,
        "provider": provider,
        "product_code": product_code,
        "provider_product_id": provider_product_id,
        "base_plan_id": _safe_str(raw.get("base_plan_id")),
        "offer_id": _safe_str(raw.get("offer_id")),
        "regions": [
            _safe_str(value).upper()
            for value in raw.get("regions") or []
            if _safe_str(value)
        ],
        "enabled": _safe_bool(raw.get("enabled"), default=True),
    }


def normalize_support_settings(raw: Any) -> Dict[str, Any]:
    current = default_support_settings()
    if not isinstance(raw, dict):
        return current
    for key in (
        "support_url",
        "faq_url",
        "manage_subscription_url",
        "refund_policy_url",
        "default_checkout_url",
    ):
        if key in raw:
            current[key] = _normalize_url(raw.get(key))
    for key in ("support_email", "sales_email"):
        if key in raw:
            current[key] = _safe_str(raw.get(key)).lower()
    if "contact_label" in raw:
        current["contact_label"] = _safe_str(raw.get("contact_label"))
    return current


def normalize_catalog_payload(
    *,
    plans: Any,
    products: Any,
    provider_products: Any = None,
    offers: Any = None,
    support: Any,
) -> Dict[str, Any]:
    normalized_plans = [normalize_plan_definition(item) for item in (plans or [])]
    known_plan_codes = {item["code"] for item in normalized_plans}
    normalized_products = [
        normalize_product_definition(item, known_plan_codes=known_plan_codes)
        for item in (products or [])
    ]
    known_product_codes = {item["code"] for item in normalized_products}
    raw_provider_products = provider_products if provider_products is not None else offers
    normalized_provider_products = [
        normalize_provider_product_definition(item, known_product_codes=known_product_codes)
        for item in (raw_provider_products or [])
    ]
    normalized_support = normalize_support_settings(support)
    return {
        "plans": sort_plans(normalized_plans),
        "products": sort_products(normalized_products),
        "provider_products": sort_provider_products(normalized_provider_products),
        "support": normalized_support,
    }
