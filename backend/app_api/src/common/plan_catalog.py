from __future__ import annotations

from copy import deepcopy
from decimal import Decimal
from typing import Any, Dict

PLAN_CODES = ("free", "starter", "producer", "studio", "enterprise", "education")
INDIVIDUAL_PLAN_CODES = {"free", "starter", "producer"}
TEAM_BUSINESS_PLAN_CODES = {"studio", "enterprise", "education"}
PLAN_PRIORITY = {
    "free": 0,
    "starter": 10,
    "producer": 20,
    "studio": 30,
    "enterprise": 40,
    "education": 50,
}

_BASE_CAPABILITIES: Dict[str, bool] = {
    "all_plugins": False,
    "high_quality_export": False,
    "wav_starter_samples": False,
    "selectable_ai_models": False,
    "advanced_ai_models": False,
    "producer_profile_presets": False,
    "premium_sound_libraries": False,
    "cloud_file_browser": False,
    "custom_sample_packs": False,
    "profile_plan_badge": False,
    "dedicated_support": False,
    "custom_ai_models": False,
    "compliance_controls": False,
    "education_sandbox": False,
    "video_projects": True,
    "web_checkout": True,
    "mobile_iap": True,
    "studio_features": False,
    "cloud_projects": False,
    "team_workspaces": False,
    "priority_support": False,
    "education_visibility_controls": False,
}

PLAN_CATALOG: Dict[str, Dict[str, Any]] = {
    "free": {
        "label": "Free",
        "group": "individual",
        "rank": 0,
        "description": "Basic DAW functionality, limited AI, starter samples, and standard sharing.",
        "capabilities": {
            "cloud_projects": True,
        },
        "limits": {
            "members": 1,
            "cloud_projects": 1,
            "storage_gb": Decimal("0.1"),
            "platform_upload_hours": 1,
            "ai_prompts_daily": 30,
            "ai_prompts_weekly": 120,
            "ai_model_tier": "standard",
            "producer_profile_presets": "mixroom_producer",
        },
    },
    "starter": {
        "label": "Starter",
        "group": "individual",
        "rank": 10,
        "description": "Expanded DAW features, WAV starter samples, higher-quality export, and more storage.",
        "capabilities": {
            "all_plugins": True,
            "high_quality_export": True,
            "wav_starter_samples": True,
            "producer_profile_presets": True,
            "cloud_projects": True,
        },
        "limits": {
            "members": 1,
            "cloud_projects": "custom",
            "storage_gb": 5,
            "platform_upload_hours": 100,
            "ai_prompts_daily": 400,
            "ai_prompts_weekly": 1500,
            "ai_model_tier": "standard",
            "producer_profile_presets": "expanded",
        },
    },
    "producer": {
        "label": "Producer",
        "group": "individual",
        "rank": 20,
        "description": "Full solo creator suite with advanced AI, premium libraries, and cloud file tools.",
        "capabilities": {
            "all_plugins": True,
            "high_quality_export": True,
            "wav_starter_samples": True,
            "selectable_ai_models": True,
            "advanced_ai_models": True,
            "producer_profile_presets": True,
            "premium_sound_libraries": True,
            "cloud_file_browser": True,
            "custom_sample_packs": True,
            "profile_plan_badge": True,
            "cloud_projects": True,
        },
        "limits": {
            "members": 1,
            "cloud_projects": "custom",
            "storage_gb": 250,
            "platform_upload_hours": 10000,
            "ai_prompts_daily": 1000,
            "ai_prompts_weekly": 4000,
            "ai_basic_prompts_daily": 1000,
            "ai_better_prompts_daily": 250,
            "ai_premium_prompts_daily": 50,
            "ai_model_tier": "advanced",
            "sample_pack_storage_gb": 250,
            "storage_addons_gb": [250, 1024, 2048],
            "producer_profile_presets": "expanded",
        },
    },
    "studio": {
        "label": "Studio",
        "group": "team",
        "rank": 30,
        "description": "Producer-level access for teams with shared project and file storage.",
        "capabilities": {
            "all_plugins": True,
            "high_quality_export": True,
            "wav_starter_samples": True,
            "selectable_ai_models": True,
            "advanced_ai_models": True,
            "producer_profile_presets": True,
            "premium_sound_libraries": True,
            "cloud_file_browser": True,
            "custom_sample_packs": True,
            "profile_plan_badge": True,
            "studio_features": True,
            "cloud_projects": True,
            "team_workspaces": True,
            "priority_support": True,
        },
        "limits": {
            "members": 5,
            "cloud_projects": "custom",
            "platform_upload_hours": 10000,
            "ai_prompts_daily": 1000,
            "ai_prompts_weekly": 4000,
            "ai_basic_prompts_daily": 1000,
            "ai_better_prompts_daily": 250,
            "ai_premium_prompts_daily": 50,
            "ai_model_tier": "advanced",
            "sample_pack_storage_gb": 1000,
            "shared_storage_gb": 1024,
            "storage_addons_gb": [1024],
            "additional_seat_price_usd_monthly": 15,
            "producer_profile_presets": "expanded",
        },
    },
    "enterprise": {
        "label": "Enterprise",
        "group": "enterprise",
        "rank": 40,
        "description": "Sales-assisted organization plan with custom integrations, compliance controls, and dedicated support.",
        "capabilities": {
            "all_plugins": True,
            "high_quality_export": True,
            "wav_starter_samples": True,
            "selectable_ai_models": True,
            "advanced_ai_models": True,
            "producer_profile_presets": True,
            "premium_sound_libraries": True,
            "cloud_file_browser": True,
            "custom_sample_packs": True,
            "profile_plan_badge": True,
            "studio_features": True,
            "cloud_projects": True,
            "team_workspaces": True,
            "priority_support": True,
            "dedicated_support": True,
            "custom_ai_models": True,
            "compliance_controls": True,
        },
        "limits": {
            "members": 500,
            "cloud_projects": "custom",
            "platform_upload_hours": "custom",
            "ai_prompts_daily": "custom",
            "ai_prompts_weekly": "custom",
            "ai_model_tier": "custom",
            "sample_pack_storage_gb": "custom",
            "shared_storage_gb": "custom",
            "producer_profile_presets": "custom",
        },
    },
    "education": {
        "label": "Education",
        "group": "education",
        "rank": 50,
        "description": "Classroom plan with Starter-level seats for teachers, academies, and institutions.",
        "capabilities": {
            "all_plugins": True,
            "high_quality_export": True,
            "wav_starter_samples": True,
            "producer_profile_presets": True,
            "cloud_projects": True,
            "team_workspaces": False,
            "education_sandbox": True,
            "compliance_controls": True,
            "education_visibility_controls": True,
        },
        "limits": {
            "members": 20,
            "seat_options": [10, 20, 30],
            "default_seats": 20,
            "cloud_projects": "custom",
            "storage_gb": 5,
            "platform_upload_hours": 100,
            "ai_prompts_daily": 400,
            "ai_prompts_weekly": 1500,
            "ai_model_tier": "standard",
            "producer_profile_presets": "expanded",
        },
    },
}

PRODUCT_CATALOG = [
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
        "price_display": "$5/mo",
        "price_krw": 6600,
        "trial_days": 30,
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
        "price_display": "$54/yr",
        "price_krw": 77000,
        "trial_days": 30,
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
        "price_display": "$20/mo",
        "price_krw": 29000,
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
        "price_display": "$216/yr",
        "price_krw": 299000,
    },
    {
        "code": "studio_monthly",
        "plan_code": "studio",
        "type": "subscription",
        "billing_interval": "monthly",
        "label": "Studio Monthly",
        "description": "Monthly Studio access for small teams.",
        "enabled": True,
        "management_channel": "web",
        "platforms": ["web"],
        "price_display": "$100/mo",
        "price_krw": 149000,
    },
    {
        "code": "studio_yearly",
        "plan_code": "studio",
        "type": "subscription",
        "billing_interval": "yearly",
        "label": "Studio Yearly",
        "description": "Annual Studio access for small teams.",
        "enabled": True,
        "management_channel": "web",
        "platforms": ["web"],
        "price_display": "$1,020/yr",
        "price_krw": 1490000,
    },
    {
        "code": "education_10_seats",
        "plan_code": "education",
        "type": "subscription",
        "billing_interval": "monthly",
        "label": "Education 10 Student Seats",
        "description": "Education access for 10 student seats. Teacher/admin access is included separately.",
        "enabled": True,
        "management_channel": "admin",
        "platforms": ["web"],
        "price_display": "Contact sales",
        "seat_limit": 10,
    },
    {
        "code": "education_20_seats",
        "plan_code": "education",
        "type": "subscription",
        "billing_interval": "monthly",
        "label": "Education 20 Student Seats",
        "description": "Education access for 20 student seats. Teacher/admin access is included separately.",
        "enabled": True,
        "management_channel": "admin",
        "platforms": ["web"],
        "price_display": "Contact sales",
        "seat_limit": 20,
    },
    {
        "code": "education_30_seats",
        "plan_code": "education",
        "type": "subscription",
        "billing_interval": "monthly",
        "label": "Education 30 Student Seats",
        "description": "Education access for 30 student seats. Teacher/admin access is included separately.",
        "enabled": True,
        "management_channel": "admin",
        "platforms": ["web"],
        "price_display": "Contact sales",
        "seat_limit": 30,
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
        "platforms": ["ios", "android", "web"],
        "price_display": "From $1,000/mo",
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
        "platforms": ["ios", "android", "web"],
        "price_display": "Contact sales",
    },
    {
        "code": "credits_100",
        "plan_code": "free",
        "type": "credits",
        "billing_interval": "one_time",
        "label": "100 Credits",
        "description": "One-time credit pack.",
        "enabled": False,
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
        "enabled": False,
        "management_channel": "web",
        "platforms": ["web"],
        "price_display": "$4.99",
    },
]

PROVIDER_PRODUCT_CATALOG = [
    {
        "code": "apple_starter_monthly",
        "provider": "apple",
        "product_code": "starter_monthly",
        "provider_product_id": "mixroom_starter_monthly",
        "enabled": True,
    },
    {
        "code": "google_starter_monthly",
        "provider": "google",
        "product_code": "starter_monthly",
        "provider_product_id": "mixroom_starter_monthly",
        "enabled": True,
    },
    {
        "code": "apple_starter_yearly",
        "provider": "apple",
        "product_code": "starter_yearly",
        "provider_product_id": "mixroom_starter_yearly",
        "enabled": True,
    },
    {
        "code": "google_starter_yearly",
        "provider": "google",
        "product_code": "starter_yearly",
        "provider_product_id": "mixroom_starter_yearly",
        "enabled": True,
    },
    {
        "code": "apple_producer_monthly",
        "provider": "apple",
        "product_code": "producer_monthly",
        "provider_product_id": "mixroom_producer_monthly",
        "enabled": True,
    },
    {
        "code": "apple_producer_yearly",
        "provider": "apple",
        "product_code": "producer_yearly",
        "provider_product_id": "mixroom_producer_yearly",
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
        "code": "google_producer_yearly",
        "provider": "google",
        "product_code": "producer_yearly",
        "provider_product_id": "mixroom_producer_yearly",
        "enabled": True,
    },
    {
        "code": "paddle_studio_monthly",
        "provider": "paddle",
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
    {
        "code": "toss_starter_yearly",
        "provider": "toss",
        "product_code": "starter_yearly",
        "provider_product_id": "mixroom_starter_yearly",
        "enabled": True,
    },
    {
        "code": "toss_producer_monthly",
        "provider": "toss",
        "product_code": "producer_monthly",
        "provider_product_id": "mixroom_producer_monthly",
        "enabled": True,
    },
    {
        "code": "toss_producer_yearly",
        "provider": "toss",
        "product_code": "producer_yearly",
        "provider_product_id": "mixroom_producer_yearly",
        "enabled": True,
    },
    {
        "code": "toss_studio_monthly",
        "provider": "toss",
        "product_code": "studio_monthly",
        "provider_product_id": "mixroom_studio_monthly",
        "enabled": True,
    },
    {
        "code": "toss_studio_yearly",
        "provider": "toss",
        "product_code": "studio_yearly",
        "provider_product_id": "mixroom_studio_yearly",
        "enabled": True,
    },
]


def _canonical_plan_code(plan_code: str) -> str:
    normalized = str(plan_code or "").strip().lower()
    if normalized == "pro":
        return "producer"
    if normalized == "basic":
        return "free"
    return normalized if normalized in PLAN_CATALOG else "free"


def default_capabilities_for_plan(plan_code: str) -> Dict[str, bool]:
    code = _canonical_plan_code(plan_code)
    capabilities = {**_BASE_CAPABILITIES}
    capabilities.update(PLAN_CATALOG[code].get("capabilities") or {})
    return capabilities


def default_limits_for_plan(plan_code: str) -> Dict[str, Any]:
    code = _canonical_plan_code(plan_code)
    return deepcopy(PLAN_CATALOG[code].get("limits") or {})


def default_plan_definitions() -> list[Dict[str, Any]]:
    definitions = []
    for code in PLAN_CODES:
        plan = PLAN_CATALOG[code]
        definitions.append(
            {
                "code": code,
                "label": plan["label"],
                "group": plan["group"],
                "rank": plan["rank"],
                "active": True,
                "description": plan["description"],
                "capabilities": default_capabilities_for_plan(code),
                "limits": default_limits_for_plan(code),
            }
        )
    return definitions


def default_product_definitions() -> list[Dict[str, Any]]:
    return deepcopy(PRODUCT_CATALOG)


def default_provider_product_definitions() -> list[Dict[str, Any]]:
    return deepcopy(PROVIDER_PRODUCT_CATALOG)


def default_support_settings() -> Dict[str, Any]:
    from . import config

    return {
        "support_email": "support@mixroom.ai",
        "sales_email": "sales@mixroom.ai",
        "enterprise_support_email": "support+enterprise@mixroom.ai",
        "support_url": "https://www.mixroom.ai/support",
        "faq_url": "https://www.mixroom.ai/support",
        "manage_subscription_url": "https://www.mixroom.ai/account",
        "refund_policy_url": "https://www.mixroom.ai/terms",
        "contact_label": "Contact support",
        "default_checkout_url": config.DEFAULT_CHECKOUT_URL,
    }
