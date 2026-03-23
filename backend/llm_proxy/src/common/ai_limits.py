from __future__ import annotations

import json
import os
import re
from functools import lru_cache
from math import ceil
from pathlib import Path
from typing import Any, Mapping

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
    raw_tier = str(
        user_data.get("subscription_tier") or user_data.get("tier") or "free"
    ).strip().lower()
    normalized = _TIER_ALIASES.get(raw_tier, raw_tier or "free")
    configured_tiers = load_ai_limits().get("tiers") or {}
    if normalized in configured_tiers:
        return normalized
    return "free"


def get_tier_limits(tier: str) -> dict[str, int]:
    configured_tiers = load_ai_limits().get("tiers") or {}
    normalized_tier = _TIER_ALIASES.get((tier or "").strip().lower(), (tier or "").strip().lower())
    limits = configured_tiers.get(normalized_tier) or configured_tiers.get("free") or {}
    return {
        "daily_credits": int(limits.get("daily_credits") or 0),
        "monthly_tokens": int(limits.get("monthly_tokens") or 0),
    }


def get_prompt_limits() -> dict[str, int]:
    prompt_limits = load_ai_limits().get("prompt_limits") or {}
    return {
        "daily_prompts": int(prompt_limits.get("daily") or 0),
        "weekly_prompts": int(prompt_limits.get("weekly") or 0),
    }


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
    raw_value = os.environ.get("LLM_MAX_OUTPUT_TOKENS", "1024").strip() or "1024"
    try:
        parsed = int(raw_value)
    except ValueError:
        return 1024
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
