from __future__ import annotations

import base64
import hashlib
import json
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from . import config
from .billing_catalog import infer_plan_code
from .models import normalize_provider, normalize_status


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class RequestBodyError(ValueError):
    def __init__(self, message: str, *, status_code: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class RequestPayloadTooLargeError(RequestBodyError):
    def __init__(self, message: str = "Request too large.") -> None:
        super().__init__(message, status_code=413)


def _read_event_body(event: Dict[str, Any]) -> str:
    body = event.get("body")
    if body is None:
        return ""
    if isinstance(body, dict):
        return json.dumps(body)
    if not isinstance(body, str):
        return ""
    if not event.get("isBase64Encoded"):
        return body
    try:
        decoded = base64.b64decode(body)
    except Exception as exc:
        raise RequestBodyError("Request body must be valid JSON.") from exc
    return decoded.decode("utf-8")


def parse_json_body(
    event: Dict[str, Any],
    *,
    max_bytes: Optional[int] = None,
) -> Dict[str, Any]:
    body = _read_event_body(event)
    if not body.strip():
        return {}

    limit_bytes = max_bytes or config.APP_API_MAX_REQUEST_BYTES
    if len(body.encode("utf-8")) > limit_bytes:
        raise RequestPayloadTooLargeError()

    try:
        parsed = json.loads(body)
    except json.JSONDecodeError as exc:
        raise RequestBodyError("Request body must be valid JSON.") from exc

    if isinstance(parsed, dict):
        return parsed
    raise RequestBodyError("Request body must be a JSON object.")


def provider_from_path(path: str) -> str:
    p = path.lower()
    if p.endswith("/stibee"):
        return "stibee"
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
    event_id = provider_event_key(provider, provider_event_id)
    now = utc_now_iso()
    normalized_payload = normalized or {}
    occurred_at = (
        normalized_payload.get("source_occurred_at")
        or payload.get("occurred_at")
        or now
    )

    return {
        "event_id": event_id,
        "provider": normalize_provider(provider),
        "provider_event_id": provider_event_id,
        "provider_provider_event_id": provider_event_key(provider, provider_event_id),
        "event_type": event_type,
        "occurred_at": occurred_at,
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
    raw_plan_code = (
        payload.get("plan_code")
        or metadata.get("plan_code")
        or payload.get("tier")
        or metadata.get("tier")
        or ""
    )
    product_code = str(
        payload.get("product_code") or metadata.get("product_code") or ""
    ).strip().lower()
    product_id = str(
        payload.get("product_id")
        or payload.get("provider_product_id")
        or metadata.get("product_id")
        or metadata.get("provider_product_id")
        or ""
    ).strip()
    plan_code = infer_plan_code(raw_plan_code) if raw_plan_code else _infer_plan_code_from_text(product_code or product_id)

    return {
        "provider": provider,
        "subscription_id": str(
            payload.get("subscription_id")
            or payload.get("id")
            or payload.get("customer_id")
            or f"{provider}-sub-unknown"
        ),
        "status": status,
        "effective_at": payload.get("effective_at") or utc_now_iso(),
        "expires_at": payload.get("expires_at"),
        "source_occurred_at": (
            payload.get("occurred_at")
            or payload.get("event_time")
            or payload.get("created_at")
            or payload.get("updated_at")
        ),
        "management_channel": provider,
        "plan_code": plan_code,
        "product_code": product_code,
        "product_id": product_id,
    }


def normalize_mobile_verify(provider: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    provider = normalize_provider(provider)
    subscription_id = str(
        payload.get("subscription_id")
        or payload.get("original_transaction_id")
        or payload.get("purchase_token")
        or f"{provider}-sub-verify"
    )
    plan_code = infer_plan_code(payload.get("plan_code") or "producer")
    status = normalize_status(str(payload.get("status") or "active"))

    return {
        "provider": provider,
        "subscription_id": subscription_id,
        "plan_code": plan_code,
        "status": status,
        "effective_at": payload.get("effective_at") or utc_now_iso(),
        "expires_at": payload.get("expires_at"),
        "management_channel": provider,
    }


def _infer_plan_code_from_text(value: str) -> str:
    normalized = str(value or "").strip().lower()
    if "education" in normalized:
        return "education"
    if "enterprise" in normalized:
        return "enterprise"
    if "studio" in normalized:
        return "studio"
    if "starter" in normalized:
        return "starter"
    if "producer" in normalized or "_pro_" in normalized or normalized.endswith("_pro"):
        return "producer"
    return "producer"
