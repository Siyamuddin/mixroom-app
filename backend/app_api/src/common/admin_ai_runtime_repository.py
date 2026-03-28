from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from . import config
from .ai_runtime_defaults import feature_default_runtime

_SUPPORTED_FEATURES = ("ai_chat", "video_editor_chat")
_SETTING_PREFIX = "ai_runtime_config#"
_MAX_MODEL_LENGTH = 120
_MAX_PROMPT_LENGTH = 120000
_MAX_CACHE_RETENTION_LENGTH = 32
_MAX_REASONING_EFFORT_LENGTH = 32
_MAX_OUTPUT_TOKENS = 32768
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


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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


class AdminAiRuntimeRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.AI_PROMPT_LIMIT_SETTINGS_TABLE:
            self._table = self._ddb.Table(config.AI_PROMPT_LIMIT_SETTINGS_TABLE)

    def get_runtime_settings(self) -> Dict[str, Any]:
        features = [self._serialize_feature(feature, self._get_item(feature)) for feature in _SUPPORTED_FEATURES]
        return {
            "features": features,
            "configurable": self._table is not None,
        }

    def update_feature_runtime(
        self,
        *,
        feature: str,
        model_override: Any,
        system_prompt_override: Any,
        max_output_tokens_override: Any,
        temperature_override: Any,
        reasoning_effort_override: Any,
        prompt_cache_retention_override: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        normalized_feature = self._validate_feature(feature)
        if self._table is None:
            raise RuntimeError("AI prompt limit settings table is not configured.")

        model_value = self._validate_optional_string(
            model_override,
            field_name="Model override",
            max_length=_MAX_MODEL_LENGTH,
        )
        if model_value and model_value not in _ALLOWED_MODEL_OVERRIDES:
            raise ValueError("Model override must be one of the approved server models.")
        prompt_value = self._validate_optional_string(
            system_prompt_override,
            field_name="System prompt override",
            max_length=_MAX_PROMPT_LENGTH,
            preserve_whitespace=True,
        )
        cache_retention_value = self._validate_optional_string(
            prompt_cache_retention_override,
            field_name="Prompt cache retention override",
            max_length=_MAX_CACHE_RETENTION_LENGTH,
        )
        if (
            cache_retention_value
            and cache_retention_value not in _ALLOWED_PROMPT_CACHE_RETENTION_OVERRIDES
        ):
            raise ValueError("Prompt cache retention override must be one of: in_memory, 24h.")
        reasoning_effort_value = self._validate_optional_string(
            reasoning_effort_override,
            field_name="Reasoning effort override",
            max_length=_MAX_REASONING_EFFORT_LENGTH,
        )
        if (
            reasoning_effort_value
            and reasoning_effort_value not in _ALLOWED_REASONING_EFFORT_OVERRIDES
        ):
            raise ValueError(
                "Reasoning effort override must be one of: minimal, low, medium, high."
            )
        max_output_tokens_value = self._validate_optional_int(
            max_output_tokens_override,
            field_name="Max output tokens override",
            minimum=1,
            maximum=_MAX_OUTPUT_TOKENS,
        )
        temperature_value = self._validate_optional_float(
            temperature_override,
            field_name="Temperature override",
            minimum=0.0,
            maximum=2.0,
        )
        current = _utc_now_iso()
        response = self._table.update_item(
            Key={"setting_key": self._item_key(normalized_feature)},
            UpdateExpression=(
                "SET feature = :feature, "
                "model_override = :model_override, "
                "system_prompt_override = :system_prompt_override, "
                "max_output_tokens_override = :max_output_tokens_override, "
                "temperature_override = :temperature_override, "
                "reasoning_effort_override = :reasoning_effort_override, "
                "prompt_cache_retention_override = :prompt_cache_retention_override, "
                "updated_at = :updated_at, "
                "updated_by_user_id = :updated_by_user_id, "
                "updated_by_email = :updated_by_email"
            ),
            ExpressionAttributeValues={
                ":feature": normalized_feature,
                ":model_override": model_value,
                ":system_prompt_override": prompt_value,
                ":max_output_tokens_override": max_output_tokens_value,
                ":temperature_override": temperature_value,
                ":reasoning_effort_override": reasoning_effort_value,
                ":prompt_cache_retention_override": cache_retention_value,
                ":updated_at": current,
                ":updated_by_user_id": _safe_str(updated_by_user_id),
                ":updated_by_email": _safe_str(updated_by_email).lower(),
            },
            ReturnValues="ALL_NEW",
        )
        return self._serialize_feature(
            normalized_feature,
            response.get("Attributes") or {},
        )

    def _get_item(self, feature: str) -> Dict[str, Any]:
        if self._table is None:
            return {}
        return (
            self._table.get_item(
                Key={"setting_key": self._item_key(feature)},
                ConsistentRead=True,
            ).get("Item")
            or {}
        )

    def _serialize_feature(self, feature: str, item: Dict[str, Any]) -> Dict[str, Any]:
        default_runtime = self._default_runtime_for_feature(feature)
        return {
            "feature": feature,
            "model_override": _safe_str(item.get("model_override")),
            "system_prompt_override": str(item.get("system_prompt_override") or ""),
            "max_output_tokens_override": _safe_int(item.get("max_output_tokens_override")),
            "temperature_override": _safe_float(item.get("temperature_override")),
            "reasoning_effort_override": _safe_str(item.get("reasoning_effort_override")),
            "prompt_cache_retention_override": _safe_str(item.get("prompt_cache_retention_override")),
            "updated_at": _safe_str(item.get("updated_at")),
            "updated_by_user_id": _safe_str(item.get("updated_by_user_id")),
            "updated_by_email": _safe_str(item.get("updated_by_email")).lower(),
            "source": "remote" if item else "default",
            "default_runtime": default_runtime,
        }

    def _default_runtime_for_feature(self, feature: str) -> Dict[str, Any]:
        return feature_default_runtime(feature)

    def _validate_feature(self, feature: Any) -> str:
        normalized = _safe_str(feature).lower()
        if normalized not in _SUPPORTED_FEATURES:
            raise ValueError("Unsupported AI feature.")
        return normalized

    def _item_key(self, feature: str) -> str:
        return f"{_SETTING_PREFIX}{feature}"

    def _validate_optional_string(
        self,
        value: Any,
        *,
        field_name: str,
        max_length: int,
        preserve_whitespace: bool = False,
    ) -> str:
        if value is None:
            return ""
        raw = str(value)
        normalized = raw if preserve_whitespace else raw.strip()
        if not normalized.strip():
            return ""
        if len(normalized) > max_length:
            raise ValueError(f"{field_name} must be {max_length:,} characters or less.")
        return normalized

    def _validate_optional_int(
        self,
        value: Any,
        *,
        field_name: str,
        minimum: int,
        maximum: int,
    ) -> int | None:
        if value in (None, ""):
            return None
        parsed = _safe_int(value)
        if parsed is None:
            raise ValueError(f"{field_name} must be a whole number.")
        if parsed < minimum or parsed > maximum:
            raise ValueError(f"{field_name} must be between {minimum:,} and {maximum:,}.")
        return parsed

    def _validate_optional_float(
        self,
        value: Any,
        *,
        field_name: str,
        minimum: float,
        maximum: float,
    ) -> float | None:
        if value in (None, ""):
            return None
        parsed = _safe_float(value)
        if parsed is None:
            raise ValueError(f"{field_name} must be numeric.")
        if parsed < minimum or parsed > maximum:
            raise ValueError(f"{field_name} must be between {minimum:g} and {maximum:g}.")
        return parsed
