from __future__ import annotations

from typing import Any, Dict

from . import config


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def default_model() -> str:
    return _safe_str(config.AI_RUNTIME_DEFAULT_MODEL) or "gpt-4.1-mini"


def chat_default_temperature() -> float:
    return float(config.AI_CHAT_DEFAULT_TEMPERATURE)


def video_default_temperature() -> float:
    return float(config.VIDEO_EDITOR_DEFAULT_TEMPERATURE)


def default_reasoning_effort(model_name: str) -> str:
    normalized = _safe_str(model_name).lower()
    return "minimal" if normalized.startswith("gpt-5") else ""


def default_prompt_cache_retention(model_name: str) -> str:
    normalized = _safe_str(model_name).lower()
    if normalized in config.AI_CHAT_EXTENDED_PROMPT_CACHE_RETENTION_MODELS:
        return "24h"
    return "in_memory"


def feature_default_runtime(feature: str) -> Dict[str, Any]:
    normalized = _safe_str(feature).lower() or "ai_chat"
    model = default_model()
    if normalized == "video_editor_chat":
        return {
            "model": model,
            "max_output_tokens": None,
            "temperature": video_default_temperature(),
            "reasoning_effort": "",
            "prompt_cache_retention": "",
        }
    return {
        "model": model,
        "max_output_tokens": None,
        "temperature": chat_default_temperature(),
        "reasoning_effort": default_reasoning_effort(model),
        "prompt_cache_retention": default_prompt_cache_retention(model),
    }
