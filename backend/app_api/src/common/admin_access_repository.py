from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import config


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_email(value: Any) -> str:
    return str(value or "").strip().lower()


class AdminAccessRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.ADMIN_ALLOWLIST_TABLE:
            self._table = self._ddb.Table(config.ADMIN_ALLOWLIST_TABLE)

    def is_email_allowed(self, email: str) -> bool:
        normalized = normalize_email(email)
        if not normalized:
            return False

        if self._table is None:
            return False

        try:
            item = self._table.get_item(Key={"email": normalized}).get("Item") or {}
        except (BotoCoreError, ClientError):
            return False
        if not item:
            return False
        return item.get("access_enabled", True) is True

    def build_allowlist_entry(
        self,
        *,
        email: str,
        invited_by: str = "",
        note: str = "",
        access_enabled: bool = True,
    ) -> dict[str, Any]:
        normalized = normalize_email(email)
        if not normalized:
            raise ValueError("Email is required.")
        return {
            "email": normalized,
            "access_enabled": bool(access_enabled),
            "invited_by": str(invited_by or "").strip(),
            "note": str(note or "").strip(),
            "updated_at": _utc_now_iso(),
        }

    def put_allowlist_entry(
        self,
        *,
        email: str,
        invited_by: str = "",
        note: str = "",
        access_enabled: bool = True,
    ) -> dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Admin allowlist table is not configured.")
        entry = self.build_allowlist_entry(
            email=email,
            invited_by=invited_by,
            note=note,
            access_enabled=access_enabled,
        )
        self._table.put_item(Item=entry)
        return entry
