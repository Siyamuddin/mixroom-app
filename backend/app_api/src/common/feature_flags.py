from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from . import config

_FLAG_SET_KEY = "feature_flags#default"
_ALLOWED_FLAGS = frozenset(
    {
        "account_plan_billing_enabled",
        "subscription_enforcement_enabled",
        "iap_purchases_enabled",
        "cloud_projects_enabled",
    }
)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    normalized = _safe_str(value).lower()
    if normalized in {"true", "1", "yes", "y", "on"}:
        return True
    if normalized in {"false", "0", "no", "n", "off"}:
        return False
    raise ValueError("Feature flag values must be booleans.")


class FeatureFlagsRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.FEATURE_FLAGS_TABLE:
            self._table = self._ddb.Table(config.FEATURE_FLAGS_TABLE)

    def get_flags(self) -> Dict[str, Any]:
        return self._serialize(self._get_item())

    def update_flags(
        self,
        *,
        flags: Any,
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Feature flags table is not configured.")

        normalized_flags = self._normalize_flags(flags)
        current = _utc_now_iso()
        response = self._table.update_item(
            Key={"flag_set_key": _FLAG_SET_KEY},
            UpdateExpression=(
                "SET kind = :kind, "
                "payload = :payload, "
                "updated_at = :updated_at, "
                "updated_by_user_id = :updated_by_user_id, "
                "updated_by_email = :updated_by_email"
            ),
            ExpressionAttributeValues={
                ":kind": "feature_flags",
                ":payload": {"flags": normalized_flags},
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
                Key={"flag_set_key": _FLAG_SET_KEY},
                ConsistentRead=True,
            ).get("Item")
            or {}
        )

    def _serialize(self, item: Dict[str, Any]) -> Dict[str, Any]:
        payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
        flags = payload.get("flags") if isinstance(payload.get("flags"), dict) else {}
        return {
            "flags": self._normalize_flags(flags, allow_empty=True),
            "updated_at": _safe_str(item.get("updated_at")),
            "updated_by_user_id": _safe_str(item.get("updated_by_user_id")),
            "updated_by_email": _safe_str(item.get("updated_by_email")).lower(),
            "source": "remote" if item else "default",
            "configurable": self._table is not None,
            "allowed_flags": sorted(_ALLOWED_FLAGS),
        }

    def _normalize_flags(
        self,
        raw: Any,
        *,
        allow_empty: bool = False,
    ) -> Dict[str, bool]:
        if not isinstance(raw, dict):
            if allow_empty:
                return {}
            raise ValueError("flags must be an object.")
        normalized: Dict[str, bool] = {}
        for key, value in raw.items():
            flag_key = _safe_str(key).lower()
            if flag_key not in _ALLOWED_FLAGS:
                raise ValueError(f"Unsupported feature flag: {flag_key or key}.")
            normalized[flag_key] = _safe_bool(value)
        return normalized
