from __future__ import annotations

import json
import os
import re
from functools import lru_cache
from datetime import datetime, timedelta, timezone
from math import ceil
from pathlib import Path
from typing import Any, Mapping

from . import config

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

_FEATURE_ALIASES = {
    "ai_chat": "ai_chat",
    "assistant": "ai_chat",
    "assistant_chat": "ai_chat",
    "chat": "ai_chat",
    "one_button_mix": "ai_chat",
    "video_editor_chat": "video_editor_chat",
    "video_chat": "video_editor_chat",
    "video_editor": "video_editor_chat",
    "video": "video_editor_chat",
    "ai_project_analysis": "ai_project_analysis",
    "project_analysis": "ai_project_analysis",
    "ai_mastering": "ai_mastering",
    "mastering": "ai_mastering",
    "stem_separate": "stem_separation",
    "stem_separation": "stem_separation",
}
_TIER_ALIASES = {
    "studio": "pro",
}
_PROMPT_LIMIT_SETTINGS_KEY = "ai_prompt_limits"
_PROMPT_LIMITS_CACHE_TTL_SECONDS = 60
_prompt_limits_cache: dict[str, Any] | None = None
_prompt_limits_cache_loaded_at: datetime | None = None
_prompt_limits_table_client = None


def _limits_path() -> Path:
    return Path(__file__).resolve().parents[1] / "config" / "ai_limits.ts"


@lru_cache(maxsize=1)
def load_ai_limits() -> dict[str, Any]:
    contents = _limits_path().read_text(encoding="utf-8").strip()
    start_index = contents.find("{")
    end_index = contents.rfind("}")
    if start_index < 0 or end_index < 0 or end_index < start_index:
        raise RuntimeError("config/ai_limits.ts does not contain a valid AI_LIMITS object.")
    json_like = contents[start_index : end_index + 1]
    json_like = re.sub(r"/\*.*?\*/", "", json_like, flags=re.DOTALL)
    json_like = re.sub(r"(^|\s)//.*?$", "", json_like, flags=re.MULTILINE)
    parsed = json.loads(json_like)
    if not isinstance(parsed, dict):
        raise RuntimeError("config/ai_limits.ts must define an object.")
    return parsed


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _normalized_tier_name(tier: str) -> str:
    raw_value = (tier or "").strip().lower()
    normalized = _TIER_ALIASES.get(raw_value, raw_value or "free")
    configured_tiers = load_ai_limits().get("tiers") or {}
    if normalized in configured_tiers:
        return normalized
    return "free"


def _default_prompt_limits_for_tier(tier: str) -> dict[str, int]:
    prompt_limits = load_ai_limits().get("prompt_limits") or {}
    normalized_tier = _normalized_tier_name(tier)

    if "daily" in prompt_limits or "weekly" in prompt_limits:
        return {
            "daily_prompts": int(prompt_limits.get("daily") or 0),
            "weekly_prompts": int(prompt_limits.get("weekly") or 0),
        }

    tier_limits = (
        prompt_limits.get(normalized_tier)
        or prompt_limits.get("free")
        or prompt_limits.get("default")
        or {}
    )
    return {
        "daily_prompts": int(tier_limits.get("daily") or 0),
        "weekly_prompts": int(tier_limits.get("weekly") or 0),
    }


def _prompt_limits_table():
    global _prompt_limits_table_client
    if _prompt_limits_table_client is not None:
        return _prompt_limits_table_client
    if boto3 is None or not config.AI_PROMPT_LIMIT_SETTINGS_TABLE:
        return None
    _prompt_limits_table_client = boto3.resource("dynamodb").Table(
        config.AI_PROMPT_LIMIT_SETTINGS_TABLE
    )
    return _prompt_limits_table_client


def _load_remote_prompt_limits() -> dict[str, Any]:
    table = _prompt_limits_table()
    if table is None:
        return {}
    return (
        table.get_item(
            Key={"setting_key": _PROMPT_LIMIT_SETTINGS_KEY},
            ConsistentRead=True,
        ).get("Item")
        or {}
    )


def _get_cached_remote_prompt_limits() -> dict[str, Any]:
    global _prompt_limits_cache, _prompt_limits_cache_loaded_at
    current = _utc_now()
    if (
        _prompt_limits_cache is not None
        and _prompt_limits_cache_loaded_at is not None
        and current - _prompt_limits_cache_loaded_at
        < timedelta(seconds=_PROMPT_LIMITS_CACHE_TTL_SECONDS)
    ):
        return dict(_prompt_limits_cache)
    try:
        _prompt_limits_cache = _load_remote_prompt_limits()
        _prompt_limits_cache_loaded_at = current
    except Exception:
        _prompt_limits_cache = {}
        _prompt_limits_cache_loaded_at = current
    return dict(_prompt_limits_cache or {})


def clear_prompt_limits_cache() -> None:
    global _prompt_limits_cache, _prompt_limits_cache_loaded_at, _prompt_limits_table_client
    _prompt_limits_cache = None
    _prompt_limits_cache_loaded_at = None
    _prompt_limits_table_client = None


def normalize_feature_name(feature: str) -> str:
    value = (feature or "").strip().lower()
    return _FEATURE_ALIASES.get(value, value)


def validate_feature(feature: str) -> str:
    normalized = normalize_feature_name(feature)
    feature_costs = load_ai_limits().get("feature_costs") or {}
    if normalized not in feature_costs:
        raise ValueError(f"Unsupported AI feature '{feature}'.")
    return normalized


def get_user_tier(user: Mapping[str, Any] | None) -> str:
    user_data = user or {}
    raw_tier = str(user_data.get("subscription_tier") or user_data.get("tier") or "free")
    return _normalized_tier_name(raw_tier)


def get_tier_limits(tier: str) -> dict[str, int]:
    configured_tiers = load_ai_limits().get("tiers") or {}
    normalized_tier = _TIER_ALIASES.get((tier or "").strip().lower(), (tier or "").strip().lower())
    limits = configured_tiers.get(normalized_tier) or configured_tiers.get("free") or {}
    return {
        "daily_credits": int(limits.get("daily_credits") or 0),
        "monthly_tokens": int(limits.get("monthly_tokens") or 0),
    }


def get_prompt_limits(tier: str = "free") -> dict[str, int]:
    limits = _default_prompt_limits_for_tier(tier)
    normalized_tier = _normalized_tier_name(tier)
    if normalized_tier != "free":
        return limits

    remote_limits = _get_cached_remote_prompt_limits()
    if remote_limits:
        daily_prompts = int(
            remote_limits.get("free_daily_prompt_limit", limits["daily_prompts"]) or 0
        )
        weekly_prompts = int(
            remote_limits.get("free_weekly_prompt_limit", limits["weekly_prompts"]) or 0
        )
        if weekly_prompts < daily_prompts:
            weekly_prompts = daily_prompts
        return {
            "daily_prompts": max(daily_prompts, 0),
            "weekly_prompts": max(weekly_prompts, 0),
        }
    return limits


def get_feature_base_cost(feature: str) -> int:
    normalized = validate_feature(feature)
    feature_costs = load_ai_limits().get("feature_costs") or {}
    return int(feature_costs.get(normalized) or 0)


def calculate_credit_cost(
    *,
    feature: str,
    promptTokens: int,
    completionTokens: int,
) -> int:
    total_tokens = max(int(promptTokens or 0), 0) + max(int(completionTokens or 0), 0)
    return get_feature_base_cost(feature) + calculate_token_cost(total_tokens)


def calculate_token_cost(total_tokens: int) -> int:
    token_ratio = load_ai_limits().get("token_ratio") or {}
    tokens_per_credit = int(token_ratio.get("tokens_per_credit") or 0)
    if tokens_per_credit <= 0:
        raise RuntimeError("config/ai_limits.ts must define token_ratio.tokens_per_credit.")
    return ceil(max(int(total_tokens or 0), 0) / tokens_per_credit)


def server_max_output_tokens() -> int:
    raw_value = os.environ.get("LLM_MAX_OUTPUT_TOKENS", "4096").strip() or "4096"
    try:
        parsed = int(raw_value)
    except ValueError:
        return 4096
    return max(parsed, 1)


def apply_server_output_token_cap(request_body: dict[str, Any]) -> None:
    max_output_tokens = server_max_output_tokens()
    requested = request_body.get("max_output_tokens")
    if not isinstance(requested, int) or requested <= 0:
        request_body["max_output_tokens"] = max_output_tokens
        return
    request_body["max_output_tokens"] = min(requested, max_output_tokens)


def estimate_prompt_tokens(request_body: Mapping[str, Any]) -> int:
    serialized = json.dumps(
        {
            "instructions": request_body.get("instructions"),
            "messages": request_body.get("messages"),
            "tools": request_body.get("tools"),
            "tool_choice": request_body.get("tool_choice"),
            "metadata": request_body.get("metadata"),
        },
        separators=(",", ":"),
        ensure_ascii=False,
        sort_keys=True,
    )
    return max(1, ceil(len(serialized) / 4))


def estimate_reserved_tokens(request_body: Mapping[str, Any]) -> int:
    max_output_tokens = request_body.get("max_output_tokens")
    requested_output_tokens = (
        int(max_output_tokens)
        if isinstance(max_output_tokens, int) and max_output_tokens > 0
        else server_max_output_tokens()
    )
    return estimate_prompt_tokens(request_body) + requested_output_tokens
