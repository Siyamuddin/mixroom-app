from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from . import config
from .ai_runtime_defaults import (
    CHAT_DEFAULT_TEMPERATURE,
    VIDEO_DEFAULT_TEMPERATURE,
    default_prompt_cache_retention,
    default_reasoning,
)
from .llm_contract import (
    SYSTEM_PROMPT as CHAT_SYSTEM_PROMPT,
)
from .video_llm_contract import (
    VIDEO_SYSTEM_PROMPT,
)

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

_SUPPORTED_FEATURES = {"ai_chat", "video_editor_chat"}
_SETTING_PREFIX = "ai_runtime_config#"
_CACHE_TTL_SECONDS = 60
_ALLOWED_MODEL_OVERRIDES = frozenset(
    {
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-5",
        "gpt-5-mini",
        "gpt-5-codex",
        "gpt-5.1",
        "gpt-5.1-codex",
        "gpt-5.1-codex-mini",
        "gpt-5.1-chat-latest",
        "gpt-5.2",
    }
)
_ALLOWED_REASONING_EFFORT_OVERRIDES = frozenset({"minimal", "low", "medium", "high"})
_ALLOWED_PROMPT_CACHE_RETENTION_OVERRIDES = frozenset({"in_memory", "24h"})
_runtime_cache: dict[str, dict[str, Any]] = {}
_runtime_cache_loaded_at: dict[str, datetime] = {}
_runtime_table = None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _safe_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _settings_table():
    global _runtime_table
    if _runtime_table is not None:
        return _runtime_table
    if boto3 is None or not config.AI_PROMPT_LIMIT_SETTINGS_TABLE:
        return None
    _runtime_table = boto3.resource("dynamodb").Table(config.AI_PROMPT_LIMIT_SETTINGS_TABLE)
    return _runtime_table


def _item_key(feature: str) -> str:
    return f"{_SETTING_PREFIX}{feature}"


def clear_ai_runtime_cache() -> None:
    global _runtime_table
    _runtime_cache.clear()
    _runtime_cache_loaded_at.clear()
    _runtime_table = None


def _default_feature_runtime(feature: str, fallback_model: str) -> dict[str, Any]:
    normalized_feature = _safe_str(feature).lower() or "ai_chat"
    if normalized_feature == "video_editor_chat":
        return {
            "feature": normalized_feature,
            "model": _safe_str(fallback_model),
            "system_prompt": VIDEO_SYSTEM_PROMPT,
            "temperature": VIDEO_DEFAULT_TEMPERATURE,
            "reasoning": None,
            "max_output_tokens": None,
            "prompt_cache_retention": "",
            "has_model_override": False,
            "has_system_prompt_override": False,
            "has_temperature_override": False,
            "has_reasoning_override": False,
            "has_max_output_tokens_override": False,
            "has_prompt_cache_retention_override": False,
            "source": "default",
        }
    resolved_model = _safe_str(fallback_model)
    return {
        "feature": "ai_chat",
        "model": resolved_model,
        "system_prompt": CHAT_SYSTEM_PROMPT,
        "temperature": CHAT_DEFAULT_TEMPERATURE,
        "reasoning": default_reasoning(resolved_model),
        "max_output_tokens": None,
        "prompt_cache_retention": default_prompt_cache_retention(resolved_model),
        "has_model_override": False,
        "has_system_prompt_override": False,
        "has_temperature_override": False,
        "has_reasoning_override": False,
        "has_max_output_tokens_override": False,
        "has_prompt_cache_retention_override": False,
        "source": "default",
    }


def _load_runtime_item(feature: str) -> dict[str, Any]:
    table = _settings_table()
    if table is None:
        return {}
    return (
        table.get_item(
            Key={"setting_key": _item_key(feature)},
            ConsistentRead=True,
        ).get("Item")
        or {}
    )


def _get_cached_runtime_item(feature: str) -> dict[str, Any]:
    current = _utc_now()
    loaded_at = _runtime_cache_loaded_at.get(feature)
    cached = _runtime_cache.get(feature)
    if (
        cached is not None
        and loaded_at is not None
        and current - loaded_at < timedelta(seconds=_CACHE_TTL_SECONDS)
    ):
        return dict(cached)
    try:
        item = _load_runtime_item(feature)
    except Exception:
        item = {}
    _runtime_cache[feature] = dict(item)
    _runtime_cache_loaded_at[feature] = current
    return dict(item)


def get_ai_feature_runtime(feature: str, *, fallback_model: str) -> dict[str, Any]:
    normalized_feature = _safe_str(feature).lower() or "ai_chat"
    if normalized_feature not in _SUPPORTED_FEATURES:
        normalized_feature = "ai_chat"

    defaults = _default_feature_runtime(normalized_feature, fallback_model)
    item = _get_cached_runtime_item(normalized_feature)
    if not item:
        return defaults

    model_override = _safe_str(item.get("model_override"))
    system_prompt_override = str(item.get("system_prompt_override") or "")
    prompt_cache_retention_override = _safe_str(item.get("prompt_cache_retention_override"))
    reasoning_effort_override = _safe_str(item.get("reasoning_effort_override"))
    temperature_override = _safe_float(item.get("temperature_override"))
    max_output_tokens_override = _safe_int(item.get("max_output_tokens_override"))

    runtime = dict(defaults)
    if model_override in _ALLOWED_MODEL_OVERRIDES:
        runtime["model"] = model_override
        runtime["has_model_override"] = True
    if system_prompt_override.strip():
        runtime["system_prompt"] = system_prompt_override
        runtime["has_system_prompt_override"] = True
    if prompt_cache_retention_override in _ALLOWED_PROMPT_CACHE_RETENTION_OVERRIDES:
        runtime["prompt_cache_retention"] = prompt_cache_retention_override
        runtime["has_prompt_cache_retention_override"] = True
    if reasoning_effort_override in _ALLOWED_REASONING_EFFORT_OVERRIDES:
        runtime["reasoning"] = {"effort": reasoning_effort_override}
        runtime["has_reasoning_override"] = True
    if temperature_override is not None:
        runtime["temperature"] = temperature_override
        runtime["has_temperature_override"] = True
    if max_output_tokens_override is not None and max_output_tokens_override > 0:
        runtime["max_output_tokens"] = max_output_tokens_override
        runtime["has_max_output_tokens_override"] = True
    runtime["source"] = "remote"
    return runtime
