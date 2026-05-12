from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from . import config

_SETTING_KEY = "ai_prompt_limits"
_DEFAULT_FREE_DAILY_PROMPT_LIMIT = 50
_DEFAULT_FREE_WEEKLY_PROMPT_LIMIT = 200
_MAX_PROMPT_LIMIT = 100000


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_int(value: Any, fallback: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(fallback)


class AdminAiPromptLimitsRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.AI_PROMPT_LIMIT_SETTINGS_TABLE:
            self._table = self._ddb.Table(config.AI_PROMPT_LIMIT_SETTINGS_TABLE)

    def get_prompt_limits(self) -> Dict[str, Any]:
        item = self._get_item()
        return self._serialize(item)

    def update_prompt_limits(
        self,
        *,
        free_daily_prompt_limit: Any,
        free_weekly_prompt_limit: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("AI prompt limit settings table is not configured.")

        daily_limit = self._validate_limit(
            free_daily_prompt_limit,
            field_name="Free daily prompt limit",
        )
        weekly_limit = self._validate_limit(
            free_weekly_prompt_limit,
            field_name="Free weekly prompt limit",
        )
        if weekly_limit < daily_limit:
            raise ValueError("Free weekly prompt limit must be greater than or equal to the daily limit.")

        current = _utc_now_iso()
        response = self._table.update_item(
            Key={"setting_key": _SETTING_KEY},
            UpdateExpression=(
                "SET free_daily_prompt_limit = :daily_limit, "
                "free_weekly_prompt_limit = :weekly_limit, "
                "updated_at = :updated_at, "
                "updated_by_user_id = :updated_by_user_id, "
                "updated_by_email = :updated_by_email"
            ),
            ExpressionAttributeValues={
                ":daily_limit": daily_limit,
                ":weekly_limit": weekly_limit,
                ":updated_at": current,
                ":updated_by_user_id": _safe_str(updated_by_user_id),
                ":updated_by_email": _safe_str(updated_by_email).lower(),
            },
            ReturnValues="ALL_NEW",
        )
        return self._serialize(response.get("Attributes") or {})

    def _get_item(self) -> Dict[str, Any]:
        if self._table is None:
            return {}
        return (
            self._table.get_item(
                Key={"setting_key": _SETTING_KEY},
                ConsistentRead=True,
            ).get("Item")
            or {}
        )

    def _serialize(self, item: Dict[str, Any]) -> Dict[str, Any]:
        daily_limit = _safe_int(
            item.get("free_daily_prompt_limit"),
            _DEFAULT_FREE_DAILY_PROMPT_LIMIT,
        )
        weekly_limit = _safe_int(
            item.get("free_weekly_prompt_limit"),
            _DEFAULT_FREE_WEEKLY_PROMPT_LIMIT,
        )
        if weekly_limit < daily_limit:
            weekly_limit = daily_limit
        return {
            "free_daily_prompt_limit": max(daily_limit, 0),
            "free_weekly_prompt_limit": max(weekly_limit, 0),
            "updated_at": _safe_str(item.get("updated_at")),
            "updated_by_user_id": _safe_str(item.get("updated_by_user_id")),
            "updated_by_email": _safe_str(item.get("updated_by_email")).lower(),
            "source": "remote" if item else "default",
            "configurable": self._table is not None,
        }

    def _validate_limit(self, value: Any, *, field_name: str) -> int:
        try:
            parsed = int(value)
        except (TypeError, ValueError):
            raise ValueError(f"{field_name} must be a whole number.") from None
        if parsed < 0:
            raise ValueError(f"{field_name} must be zero or greater.")
        if parsed > _MAX_PROMPT_LIMIT:
            raise ValueError(f"{field_name} must be {_MAX_PROMPT_LIMIT:,} or less.")
        return parsed
