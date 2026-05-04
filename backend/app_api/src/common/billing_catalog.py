from __future__ import annotations

from copy import deepcopy
import re
from typing import Any, Dict, Iterable

from . import config
from .models import normalize_provider, normalize_tier

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
                if isinstance(existing, (int, float)):
                    result[normalized_key] = max(existing, value)
                else:
                    result[normalized_key] = value
                continue
            normalized_value = _safe_str(value)
            if not normalized_value:
                continue
            existing = result.get(normalized_key)
            if existing in (None, ""):
                result[normalized_key] = normalized_value
    return result


def legacy_tier_for_plan(plan_code: str) -> str:
    normalized = _safe_str(plan_code).lower()
    if normalized in {"studio", "enterprise", "education"}:
        return "studio"
    if normalized in {"starter", "producer"}:
        return "pro"
    return "free"


def infer_plan_code(raw_plan_code: Any, raw_tier: Any = "") -> str:
    normalized_plan_code = _safe_str(raw_plan_code).lower()
    if normalized_plan_code in default_plan_codes():
        return normalized_plan_code
    normalized_tier = normalize_tier(_safe_str(raw_tier))
    if normalized_tier == "studio":
        return "studio"
    if normalized_tier == "pro":
        return "producer"
    return "free"


def default_support_settings() -> Dict[str, Any]:
    return {
        "support_email": "support@mixroom.ai",
        "support_url": "https://www.mixroom.ai/support",
        "faq_url": "https://www.mixroom.ai/support",
        "manage_subscription_url": "https://www.mixroom.ai/account",
        "refund_policy_url": "https://www.mixroom.ai/terms",
        "contact_label": "Contact support",
        "default_checkout_url": config.DEFAULT_CHECKOUT_URL,
    }


def default_plan_definitions() -> list[Dict[str, Any]]:
    studio_features_enabled = bool(config.ALLOW_STUDIO_TIER)
    return [
        {
            "code": "free",
            "label": "Free",
            "group": "individual",
            "rank": 0,
            "active": True,
            "legacy_tier": "free",
            "description": "Core local projects with no cloud collaboration.",
            "capabilities": {
                "pro_editor": False,
                "unlimited_audio_tracks": False,
                "multi_video_import": False,
                "premium_effects": False,
                "video_projects": True,
                "web_checkout": True,
                "mobile_iap": True,
                "studio_features": False,
                "cloud_projects": False,
                "team_workspaces": False,
                "priority_support": False,
                "education_visibility_controls": False,
            },
            "limits": {
                "members": 1,
                "workspaces": 0,
                "cloud_projects": 0,
                "storage_gb": 0,
            },
        },
        {
            "code": "starter",
            "label": "Starter",
            "group": "individual",
            "rank": 10,
            "active": True,
            "legacy_tier": "pro",
            "description": "Entry paid tier for solo creators.",
            "capabilities": {
                "pro_editor": True,
                "unlimited_audio_tracks": True,
                "multi_video_import": True,
                "premium_effects": False,
                "video_projects": True,
                "web_checkout": True,
                "mobile_iap": True,
                "studio_features": False,
                "cloud_projects": False,
                "team_workspaces": False,
                "priority_support": False,
                "education_visibility_controls": False,
            },
            "limits": {
                "members": 1,
                "workspaces": 0,
                "cloud_projects": 0,
                "storage_gb": 5,
            },
        },
        {
            "code": "producer",
            "label": "Producer",
            "group": "individual",
            "rank": 20,
            "active": True,
            "legacy_tier": "pro",
            "description": "Full solo creator tier with premium tools.",
            "capabilities": {
                "pro_editor": True,
                "unlimited_audio_tracks": True,
                "multi_video_import": True,
                "premium_effects": True,
                "video_projects": True,
                "web_checkout": True,
                "mobile_iap": True,
                "studio_features": False,
                "cloud_projects": False,
                "team_workspaces": False,
                "priority_support": False,
                "education_visibility_controls": False,
            },
            "limits": {
                "members": 1,
                "workspaces": 0,
                "cloud_projects": 0,
                "storage_gb": 20,
            },
        },
        {
            "code": "studio",
            "label": "Studio",
            "group": "team",
            "rank": 30,
            "active": True,
            "legacy_tier": "studio",
            "description": "Small team plan with shared workspaces and cloud projects.",
            "capabilities": {
                "pro_editor": True,
                "unlimited_audio_tracks": True,
                "multi_video_import": True,
                "premium_effects": True,
                "video_projects": True,
                "web_checkout": True,
                "mobile_iap": True,
                "studio_features": studio_features_enabled,
                "cloud_projects": True,
                "team_workspaces": True,
                "priority_support": True,
                "education_visibility_controls": False,
            },
            "limits": {
                "members": 5,
                "workspaces": 3,
                "cloud_projects": 50,
                "storage_gb": 200,
            },
        },
        {
            "code": "enterprise",
            "label": "Enterprise",
            "group": "enterprise",
            "rank": 40,
            "active": True,
            "legacy_tier": "studio",
            "description": "Large organization plan with manual contract activation.",
            "capabilities": {
                "pro_editor": True,
                "unlimited_audio_tracks": True,
                "multi_video_import": True,
                "premium_effects": True,
                "video_projects": True,
                "web_checkout": False,
                "mobile_iap": False,
                "studio_features": True,
                "cloud_projects": True,
                "team_workspaces": True,
                "priority_support": True,
                "education_visibility_controls": False,
            },
            "limits": {
                "members": 500,
                "workspaces": 100,
                "cloud_projects": 5000,
                "storage_gb": 5000,
            },
        },
        {
            "code": "education",
            "label": "Education",
            "group": "education",
            "rank": 50,
            "active": True,
            "legacy_tier": "studio",
            "description": "Education plan with privacy-aware classroom collaboration.",
            "capabilities": {
                "pro_editor": True,
                "unlimited_audio_tracks": True,
                "multi_video_import": True,
                "premium_effects": True,
                "video_projects": True,
                "web_checkout": False,
                "mobile_iap": False,
                "studio_features": studio_features_enabled,
                "cloud_projects": True,
                "team_workspaces": True,
                "priority_support": True,
                "education_visibility_controls": True,
            },
            "limits": {
                "members": 200,
                "workspaces": 40,
                "cloud_projects": 1000,
                "storage_gb": 1000,
            },
        },
    ]


def default_product_definitions() -> list[Dict[str, Any]]:
    return [
        {
            "code": "starter_monthly",
            "plan_code": "starter",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Starter Monthly",
            "description": "Monthly Starter access.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$9.99/mo",
        },
        {
            "code": "starter_yearly",
            "plan_code": "starter",
            "type": "subscription",
            "billing_interval": "yearly",
            "label": "Starter Yearly",
            "description": "Annual Starter access.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$95.99/yr",
        },
        {
            "code": "producer_monthly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Producer Monthly",
            "description": "Monthly Producer access.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$19.99/mo",
        },
        {
            "code": "producer_yearly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "yearly",
            "label": "Producer Yearly",
            "description": "Annual Producer access.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$191.99/yr",
        },
        {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "description": "Monthly Studio access for small teams.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$49.99/mo",
        },
        {
            "code": "studio_yearly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "yearly",
            "label": "Studio Yearly",
            "description": "Annual Studio access for small teams.",
            "enabled": True,
            "management_channel": "web_or_mobile",
            "platforms": ["ios", "android", "web"],
            "price_display": "$479.99/yr",
        },
        {
            "code": "enterprise_contract",
            "plan_code": "enterprise",
            "type": "contract",
            "billing_interval": "custom",
            "label": "Enterprise Contract",
            "description": "Manual enterprise contract activation.",
            "enabled": True,
            "management_channel": "admin",
            "platforms": ["admin"],
            "price_display": "Contact sales",
        },
        {
            "code": "education_contract",
            "plan_code": "education",
            "type": "contract",
            "billing_interval": "custom",
            "label": "Education Contract",
            "description": "Manual education contract activation.",
            "enabled": True,
            "management_channel": "admin",
            "platforms": ["admin"],
            "price_display": "Contact sales",
        },
        {
            "code": "credits_100",
            "plan_code": "free",
            "type": "credits",
            "billing_interval": "one_time",
            "label": "100 Credits",
            "description": "One-time credit pack.",
            "enabled": True,
            "management_channel": "web",
            "platforms": ["web"],
            "price_display": "$9.99",
        },
        {
            "code": "day_pass",
            "plan_code": "producer",
            "type": "day_pass",
            "billing_interval": "daily",
            "label": "24h Day Pass",
            "description": "Temporary Producer access for one day.",
            "enabled": True,
            "management_channel": "web",
            "platforms": ["web"],
            "price_display": "$4.99",
        },
    ]


def default_offer_definitions() -> list[Dict[str, Any]]:
    return [
        {
            "code": "apple_producer_monthly",
            "provider": "apple",
            "product_code": "producer_monthly",
            "provider_product_id": "mixroom_producer_monthly",
            "enabled": True,
        },
        {
            "code": "google_producer_monthly",
            "provider": "google",
            "product_code": "producer_monthly",
            "provider_product_id": "mixroom_producer_monthly",
            "enabled": True,
        },
        {
            "code": "apple_studio_monthly",
            "provider": "apple",
            "product_code": "studio_monthly",
            "provider_product_id": "mixroom_studio_monthly",
            "enabled": True,
        },
        {
            "code": "google_studio_monthly",
            "provider": "google",
            "product_code": "studio_monthly",
            "provider_product_id": "mixroom_studio_monthly",
            "enabled": True,
        },
        {
            "code": "paddle_studio_yearly",
            "provider": "paddle",
            "product_code": "studio_yearly",
            "provider_product_id": "mixroom_studio_yearly",
            "enabled": True,
        },
        {
            "code": "toss_starter_monthly",
            "provider": "toss",
            "product_code": "starter_monthly",
            "provider_product_id": "mixroom_starter_monthly",
            "enabled": True,
        },
    ]


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
        "offers": sort_offers(default_offer_definitions()),
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


def sort_offers(offers: Iterable[Dict[str, Any]]) -> list[Dict[str, Any]]:
    return sorted(
        [deepcopy(item) for item in offers if isinstance(item, dict)],
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
    resolved = infer_plan_code(plan_code)
    plans = (catalog or default_catalog()).get("plans") or []
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
    legacy_tier = normalize_tier(_safe_str(raw.get("legacy_tier") or legacy_tier_for_plan(code)))
    return {
        "code": code,
        "label": label,
        "group": group,
        "rank": _safe_int(raw.get("rank"), default=999),
        "active": _safe_bool(raw.get("active"), default=True),
        "legacy_tier": legacy_tier,
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
    plan_code = infer_plan_code(raw.get("plan_code"))
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
        "rank": _safe_int(raw.get("rank"), default=999),
    }


def normalize_offer_definition(raw: Any, *, known_product_codes: set[str]) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError("Each billing offer must be an object.")
    code = _validate_code(raw.get("code"), field_name="Offer code")
    provider = normalize_provider(raw.get("provider"))
    if provider == "unknown":
        raise ValueError("Billing offer provider is invalid.")
    product_code = _validate_code(raw.get("product_code"), field_name="Offer product_code")
    if product_code not in known_product_codes:
        raise ValueError(f"Unknown product_code for offer {code}.")
    provider_product_id = _safe_str(raw.get("provider_product_id"))
    if not provider_product_id:
        raise ValueError("Offer provider_product_id is required.")
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
    if "support_email" in raw:
        current["support_email"] = _safe_str(raw.get("support_email")).lower()
    if "contact_label" in raw:
        current["contact_label"] = _safe_str(raw.get("contact_label"))
    return current


def normalize_catalog_payload(
    *,
    plans: Any,
    products: Any,
    offers: Any,
    support: Any,
) -> Dict[str, Any]:
    normalized_plans = [normalize_plan_definition(item) for item in (plans or [])]
    known_plan_codes = {item["code"] for item in normalized_plans}
    normalized_products = [
        normalize_product_definition(item, known_plan_codes=known_plan_codes)
        for item in (products or [])
    ]
    known_product_codes = {item["code"] for item in normalized_products}
    normalized_offers = [
        normalize_offer_definition(item, known_product_codes=known_product_codes)
        for item in (offers or [])
    ]
    normalized_support = normalize_support_settings(support)
    return {
        "plans": sort_plans(normalized_plans),
        "products": sort_products(normalized_products),
        "offers": sort_offers(normalized_offers),
        "support": normalized_support,
    }

