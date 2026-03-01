from __future__ import annotations

import uuid
from typing import Any, Dict

from common.auth import json_response
from common.events import (
    build_event_record,
    normalize_webhook,
    parse_json_body,
    provider_from_path,
)
from common.providers import verify_webhook_signature
from common.repository import BillingRepository

repo = BillingRepository()


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _header_map(event: Dict[str, Any]) -> Dict[str, str]:
    headers = event.get("headers") or {}
    return {str(k): str(v) for k, v in headers.items()}


def _resolve_provider_event_id(payload: Dict[str, Any]) -> str:
    keys = (
        "event_id",
        "id",
        "notification_uuid",
        "message_id",
        "tx_id",
    )
    for key in keys:
        value = str(payload.get(key) or "").strip()
        if value:
            return value
    return str(uuid.uuid4())


def _resolve_user_id(payload: Dict[str, Any]) -> str:
    metadata = payload.get("metadata") or {}
    if isinstance(metadata, dict):
        for key in ("mixroom_user_id", "user_id", "sub"):
            value = str(metadata.get(key) or "").strip()
            if value:
                return value

    for key in ("mixroom_user_id", "user_id", "sub"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value

    return ""


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    provider = provider_from_path(path)

    payload = parse_json_body(event)
    headers = _header_map(event)

    if not verify_webhook_signature(provider, headers, event.get("body") or ""):
        return json_response(401, {"error": "Invalid webhook signature"})

    provider_event_id = _resolve_provider_event_id(payload)
    user_id = _resolve_user_id(payload)
    normalized = normalize_webhook(provider, payload)

    record = build_event_record(
        provider=provider,
        provider_event_id=provider_event_id,
        event_type=str(payload.get("event_type") or "webhook_event"),
        user_id=user_id,
        payload=payload,
        normalized=normalized,
    )

    inserted = repo.put_billing_event_if_new(record)
    if inserted:
        repo.enqueue_projection(record["event_id"])

    return json_response(
        202,
        {
            "accepted": inserted,
            "provider": provider,
            "event_id": record["event_id"],
        },
    )
