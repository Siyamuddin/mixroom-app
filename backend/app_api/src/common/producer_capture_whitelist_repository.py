from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from . import config
from .users import normalize_username, validate_username

_SETTING_KEY = "producer_capture_ui_whitelist"
_DEFAULT_USERNAMES = ("lavitababy1004", "andrewtest")
_MAX_WHITELIST_SIZE = 1000


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _normalize_username_or_empty(value: Any) -> str:
    normalized = normalize_username(_safe_str(value))
    if not normalized:
        return ""
    validation_error = validate_username(normalized)
    if validation_error:
        return ""
    return normalized


class ProducerCaptureWhitelistRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.PRODUCER_CAPTURE_WHITELIST_TABLE:
            self._table = self._ddb.Table(config.PRODUCER_CAPTURE_WHITELIST_TABLE)

    def get_whitelist_settings(self) -> Dict[str, Any]:
        item = self._get_item()
        return self._serialize(item)

    def update_whitelist_settings(
        self,
        *,
        usernames: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Producer capture whitelist table is not configured.")

        normalized_usernames = self._validate_usernames(usernames)
        current = _utc_now_iso()
        response = self._table.update_item(
            Key={"setting_key": _SETTING_KEY},
            UpdateExpression=(
                "SET usernames = :usernames, "
                "updated_at = :updated_at, "
                "updated_by_user_id = :updated_by_user_id, "
                "updated_by_email = :updated_by_email"
            ),
            ExpressionAttributeValues={
                ":usernames": normalized_usernames,
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
        usernames = (
            self._coerce_stored_usernames(item.get("usernames"))
            if item
            else list(_DEFAULT_USERNAMES)
        )
        return {
            "usernames": usernames,
            "updated_at": _safe_str(item.get("updated_at")),
            "updated_by_user_id": _safe_str(item.get("updated_by_user_id")),
            "updated_by_email": _safe_str(item.get("updated_by_email")).lower(),
            "source": "remote" if item else "default",
            "configurable": self._table is not None,
        }

    def _coerce_stored_usernames(self, value: Any) -> List[str]:
        if not isinstance(value, list):
            return []
        unique: List[str] = []
        seen: set[str] = set()
        for raw in value:
            normalized = _normalize_username_or_empty(raw)
            if not normalized or normalized in seen:
                continue
            seen.add(normalized)
            unique.append(normalized)
        return unique

    def _validate_usernames(self, value: Any) -> List[str]:
        if value is None:
            raise ValueError("Usernames must be provided.")
        if not isinstance(value, list):
            raise ValueError("Usernames must be provided as a list.")
        if len(value) > _MAX_WHITELIST_SIZE:
            raise ValueError(
                f"Producer capture whitelist must contain {_MAX_WHITELIST_SIZE:,} usernames or fewer."
            )

        unique: List[str] = []
        seen: set[str] = set()
        for index, raw in enumerate(value):
            normalized = normalize_username(_safe_str(raw))
            if not normalized:
                continue
            validation_error = validate_username(normalized)
            if validation_error:
                raise ValueError(
                    f"Invalid username at index {index}: {validation_error}"
                )
            if normalized in seen:
                continue
            seen.add(normalized)
            unique.append(normalized)
        return unique
