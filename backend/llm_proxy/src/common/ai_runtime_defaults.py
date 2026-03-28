from __future__ import annotations

from typing import Any

from . import config


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


DEFAULT_MODEL = _safe_str(config.AI_RUNTIME_DEFAULT_MODEL) or "gpt-4.1-mini"
CHAT_DEFAULT_TEMPERATURE = float(config.AI_CHAT_DEFAULT_TEMPERATURE)
VIDEO_DEFAULT_TEMPERATURE = float(config.VIDEO_EDITOR_DEFAULT_TEMPERATURE)
DEFAULT_PROMPT_CACHE_RETENTION = "in_memory"


def default_reasoning_effort(model_name: str) -> str:
    normalized = _safe_str(model_name).lower()
    return "minimal" if normalized.startswith("gpt-5") else ""


def default_reasoning(model_name: str) -> dict[str, str] | None:
    effort = default_reasoning_effort(model_name)
    return {"effort": effort} if effort else None


def default_prompt_cache_retention(model_name: str) -> str:
    normalized = _safe_str(model_name).lower()
    if normalized in config.AI_CHAT_EXTENDED_PROMPT_CACHE_RETENTION_MODELS:
        return "24h"
    return DEFAULT_PROMPT_CACHE_RETENTION
