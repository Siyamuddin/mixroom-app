from __future__ import annotations

import time
from dataclasses import dataclass
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


@dataclass(frozen=True)
class RateLimitDecision:
    allowed: bool
    retry_after_seconds: int = 0
    reason: str = ""


class RequestRateLimiter:
    def __init__(self) -> None:
        self._ddb = (
            boto3.resource("dynamodb")
            if boto3 is not None and config.AUTH_RATE_LIMITS_TABLE
            else None
        )
        self._table = (
            self._ddb.Table(config.AUTH_RATE_LIMITS_TABLE) if self._ddb is not None else None
        )

    def enforce(
        self,
        *,
        scope_key: str,
        limit: int,
        window_seconds: int,
        block_seconds: int | None = None,
    ) -> RateLimitDecision:
        normalized_scope = str(scope_key or "").strip()
        if (
            self._table is None
            or not normalized_scope
            or limit <= 0
            or window_seconds <= 0
        ):
            return RateLimitDecision(True)

        now = int(time.time())
        item = self._get_item(normalized_scope)

        blocked_until = int(item.get("blocked_until") or 0)
        if blocked_until > now:
            return RateLimitDecision(
                False,
                retry_after_seconds=max(1, blocked_until - now),
                reason="blocked",
            )

        window_started_at = int(item.get("window_started_at") or 0)
        attempts = int(item.get("attempts") or 0)
        if window_started_at <= 0 or now - window_started_at >= window_seconds:
            window_started_at = now
            attempts = 0

        attempts += 1
        next_block_seconds = max(int(block_seconds or 0), window_seconds)
        blocked_until = now + next_block_seconds if attempts > limit else 0
        expires_at_ttl = max(window_started_at + window_seconds, blocked_until or 0, now) + 86400

        payload = {
            "scope_key": normalized_scope,
            "window_started_at": window_started_at,
            "attempts": attempts,
            "last_attempt_at": now,
            "blocked_until": blocked_until,
            "expires_at_ttl": expires_at_ttl,
            "updated_at_epoch": now,
        }
        self._put_item(payload)

        if blocked_until > now:
            return RateLimitDecision(
                False,
                retry_after_seconds=max(1, blocked_until - now),
                reason="limit_exceeded",
            )
        return RateLimitDecision(True)

    def _get_item(self, scope_key: str) -> dict[str, Any]:
        try:
            item = self._table.get_item(
                Key={"scope_key": scope_key},
                ConsistentRead=True,
            ).get("Item")
        except (BotoCoreError, ClientError):
            return {}
        return item if isinstance(item, dict) else {}

    def _put_item(self, payload: dict[str, Any]) -> None:
        try:
            self._table.put_item(Item=payload)
        except (BotoCoreError, ClientError):
            return


def client_ip_from_event(event: dict[str, Any]) -> str:
    headers = event.get("headers") or {}
    forwarded_for = str(
        headers.get("x-forwarded-for") or headers.get("X-Forwarded-For") or ""
    ).strip()
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()

    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    source_ip = str(
        http.get("sourceIp")
        or request_context.get("identity", {}).get("sourceIp")
        or ""
    ).strip()
    return source_ip
