from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from .models import normalize_provider, normalize_status, normalize_tier


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_json_body(event: Dict[str, Any]) -> Dict[str, Any]:
    body = event.get("body")
    if body is None:
        return {}
    if isinstance(body, dict):
        return body
    if not isinstance(body, str):
        return {}
    if not body.strip():
        return {}
    parsed = json.loads(body)
    if isinstance(parsed, dict):
        return parsed
    return {}


def provider_from_path(path: str) -> str:
    p = path.lower()
    if p.endswith("/apple"):
        return "apple"
    if p.endswith("/google"):
        return "google"
    if p.endswith("/paddle"):
        return "paddle"
    if p.endswith("/toss"):
        return "toss"
    return "unknown"


def hash_payload(payload: Dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def provider_event_key(provider: str, provider_event_id: str) -> str:
    return f"{provider}:{provider_event_id}"


def build_event_record(
    *,
    provider: str,
    provider_event_id: str,
    event_type: str,
    user_id: str,
    payload: Dict[str, Any],
    normalized: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    event_id = str(uuid.uuid4())
    now = utc_now_iso()
    normalized_payload = normalized or {}

    return {
        "event_id": event_id,
        "provider": normalize_provider(provider),
        "provider_event_id": provider_event_id,
        "provider_provider_event_id": provider_event_key(provider, provider_event_id),
        "event_type": event_type,
        "occurred_at": payload.get("occurred_at") or now,
        "user_id": user_id,
        "raw_payload": payload,
        "raw_payload_hash": hash_payload(payload),
        "raw_payload_ref": f"inline://{event_id}",
        "normalized": normalized_payload,
        "processed_at": None,
        "processing_result": "queued",
        "created_at": now,
    }


def normalize_webhook(provider: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    provider = normalize_provider(provider)
    metadata = payload.get("metadata") or {}
    if not isinstance(metadata, dict):
        metadata = {}

    status = normalize_status(str(payload.get("status") or payload.get("subscription_status") or "active"))
    tier = normalize_tier(str(payload.get("tier") or metadata.get("tier") or "pro"))

    return {
        "provider": provider,
        "subscription_id": str(
            payload.get("subscription_id")
            or payload.get("id")
            or payload.get("customer_id")
            or f"{provider}-sub-unknown"
        ),
        "tier": tier,
        "status": status,
        "effective_at": payload.get("effective_at") or utc_now_iso(),
        "expires_at": payload.get("expires_at"),
        "management_channel": provider,
    }


def normalize_mobile_verify(provider: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    provider = normalize_provider(provider)
    subscription_id = str(
        payload.get("subscription_id")
        or payload.get("original_transaction_id")
        or payload.get("purchase_token")
        or f"{provider}-sub-verify"
    )
    tier = normalize_tier(str(payload.get("tier") or "pro"))
    status = normalize_status(str(payload.get("status") or "active"))

    return {
        "provider": provider,
        "subscription_id": subscription_id,
        "tier": tier,
        "status": status,
        "effective_at": payload.get("effective_at") or utc_now_iso(),
        "expires_at": payload.get("expires_at"),
        "management_channel": provider,
    }
