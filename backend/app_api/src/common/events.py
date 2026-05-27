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
    if provider == "paddle":
        return _normalize_paddle_webhook(payload)
    if provider == "toss":
        return _normalize_toss_webhook(payload)

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


_TOSS_STATUS_MAP = {
    "DONE": "active",
    "PAID": "active",
    "CONFIRMED": "active",
    "IN_PROGRESS": "trialing",
    "READY": "trialing",
    "WAITING_FOR_DEPOSIT": "past_due",
    "CANCELED": "canceled",
    "PARTIAL_CANCELED": "active",
    "ABORTED": "expired",
    "EXPIRED": "expired",
}


def _normalize_toss_webhook(payload: Dict[str, Any]) -> Dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    metadata: Dict[str, Any] = {}
    for source in (
        payload.get("metadata"),
        payload.get("custom_data"),
        data.get("metadata"),
        data.get("custom_data"),
    ):
        if isinstance(source, dict):
            metadata.update(source)

    raw_status = str(data.get("status") or payload.get("status") or "DONE").strip().upper()
    product_code = str(
        data.get("product_code")
        or metadata.get("product_code")
        or metadata.get("plan_key")
        or ""
    ).strip().lower()
    plan_code = infer_plan_code(
        data.get("plan_code")
        or metadata.get("plan_code")
        or metadata.get("plan_key")
        or product_code
    )
    payment_key = str(data.get("paymentKey") or data.get("payment_key") or "").strip()
    order_id = str(data.get("orderId") or data.get("order_id") or "").strip()
    customer_key = str(
        data.get("customerKey")
        or data.get("customer_key")
        or metadata.get("customerKey")
        or metadata.get("customer_key")
        or ""
    ).strip()
    return {
        "provider": "toss",
        "subscription_id": str(
            metadata.get("subscription_id")
            or data.get("subscription_id")
            or payment_key
            or order_id
            or f"toss-sub-unknown"
        ).strip(),
        "customer_id": customer_key,
        "customer_email": str(
            data.get("customerEmail")
            or data.get("customer_email")
            or metadata.get("customer_email")
            or ""
        ).strip().lower(),
        "payment_method": _safe_payment_method(data),
        "status": normalize_status(_TOSS_STATUS_MAP.get(raw_status, raw_status.lower())),
        "effective_at": (
            data.get("approvedAt")
            or data.get("approved_at")
            or payload.get("createdAt")
            or utc_now_iso()
        ),
        "expires_at": metadata.get("expires_at") or data.get("expires_at"),
        "source_occurred_at": payload.get("createdAt") or data.get("approvedAt"),
        "next_billed_at": metadata.get("next_billed_at") or data.get("next_billed_at"),
        "management_channel": "web",
        "plan_code": plan_code,
        "product_code": product_code,
        "product_id": order_id,
        "payment_key": payment_key,
        "billing_key_parameter_name": metadata.get("billing_key_parameter_name"),
        "billing_key_secret_arn": metadata.get("billing_key_secret_arn"),
        "billing_amount": metadata.get("billing_amount"),
        "billing_currency": metadata.get("billing_currency"),
        "cancel_at_period_end": bool(metadata.get("cancel_at_period_end") or False),
        "seat_count": metadata.get("seat_count"),
        "extra_storage_tb": metadata.get("extra_storage_tb"),
    }


_PADDLE_PLAN_KEYS = {
    "starter": "starter",
    "producer": "producer",
    "studio": "studio",
}
_PADDLE_STATUS_BY_EVENT_TYPE = {
    "subscription.created": "active",
    "subscription.activated": "active",
    "subscription.updated": "active",
    "subscription.trialing": "trialing",
    "subscription.past_due": "past_due",
    "subscription.paused": "paused",
    "subscription.canceled": "canceled",
    "transaction.completed": "active",
    "transaction.payment_failed": "past_due",
    "transaction.canceled": "canceled",
    "transaction.refunded": "refunded",
}


def _safe_payment_method(source: Dict[str, Any]) -> Dict[str, Any]:
    raw = source.get("payment_method") or source.get("paymentMethod") or source.get("card")
    if not isinstance(raw, dict):
        return {}
    card = raw.get("card") if isinstance(raw.get("card"), dict) else raw
    return {
        "brand": str(card.get("brand") or card.get("cardCompany") or "").strip(),
        "last4": str(card.get("last4") or card.get("lastFourDigits") or "").strip(),
        "exp_month": card.get("exp_month") or card.get("expiryMonth"),
        "exp_year": card.get("exp_year") or card.get("expiryYear"),
    }


def _normalize_paddle_webhook(payload: Dict[str, Any]) -> Dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    metadata = _paddle_metadata(data, payload)
    items = data.get("items") if isinstance(data.get("items"), list) else []
    plan_key = _paddle_plan_key(metadata, items)
    plan_code = _PADDLE_PLAN_KEYS.get(plan_key)
    if not plan_code:
        plan_code = _infer_plan_code_from_text(
            _paddle_product_code(metadata, items)
            or _paddle_product_id(metadata, items)
            or plan_key
        )

    product_code = _paddle_product_code(metadata, items)
    product_id = _paddle_product_id(metadata, items)
    event_type = str(payload.get("event_type") or "").strip().lower()
    scheduled_change = data.get("scheduled_change") if isinstance(data.get("scheduled_change"), dict) else {}
    cancel_at_period_end = (
        str(scheduled_change.get("action") or "").strip().lower() == "cancel"
        and bool(scheduled_change.get("effective_at"))
    )
    status = normalize_status(
        str(
            ("active" if cancel_at_period_end and event_type == "subscription.updated" else None)
            or _PADDLE_STATUS_BY_EVENT_TYPE.get(event_type)
            or data.get("status")
            or "active"
        )
    )
    subscription_id = str(
        data.get("subscription_id")
        or data.get("id")
        or metadata.get("subscription_id")
        or "paddle-sub-unknown"
    ).strip()

    normalized: Dict[str, Any] = {
        "provider": "paddle",
        "subscription_id": subscription_id,
        "customer_id": _paddle_customer_id(data, payload),
        "customer_email": _paddle_customer_email(data, payload),
        "payment_method": _safe_payment_method(data),
        "status": status,
        "effective_at": (
            data.get("started_at")
            or data.get("created_at")
            or data.get("billed_at")
            or payload.get("occurred_at")
            or utc_now_iso()
        ),
        "expires_at": _paddle_expires_at(data),
        "source_occurred_at": (
            payload.get("occurred_at")
            or data.get("updated_at")
            or data.get("created_at")
        ),
        "next_billed_at": data.get("next_billed_at"),
        "management_channel": "web",
        "plan_code": plan_code,
        "product_code": product_code,
        "product_id": product_id,
        "cancel_at_period_end": cancel_at_period_end,
    }

    if plan_code == "studio":
        additional_seats = _paddle_quantity_for_plan_key(items, "studio_seat_addon")
        storage_blocks = _paddle_quantity_for_plan_key(items, "storage_1tb_addon")
        normalized["seat_count"] = 5 + additional_seats
        normalized["extra_storage_tb"] = storage_blocks
    return normalized


def _paddle_customer_id(data: Dict[str, Any], payload: Dict[str, Any]) -> str:
    for source in (data, payload):
        value = str(source.get("customer_id") or "").strip()
        if value:
            return value
    for container in (data.get("customer"), payload.get("customer")):
        if isinstance(container, dict):
            value = str(container.get("id") or "").strip()
            if value:
                return value
    return ""


def _paddle_customer_email(data: Dict[str, Any], payload: Dict[str, Any]) -> str:
    for container in (data.get("customer"), payload.get("customer")):
        if isinstance(container, dict):
            value = str(container.get("email") or "").strip().lower()
            if value:
                return value
    return str(data.get("customer_email") or payload.get("customer_email") or "").strip().lower()


def _paddle_expires_at(data: Dict[str, Any]) -> Any:
    ends_at = data.get("ends_at")
    if ends_at:
        return ends_at
    scheduled_change = data.get("scheduled_change")
    if isinstance(scheduled_change, dict):
        return scheduled_change.get("effective_at")
    return None


def _paddle_metadata(data: Dict[str, Any], payload: Dict[str, Any]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for source in (
        payload.get("metadata"),
        payload.get("custom_data"),
        data.get("metadata"),
        data.get("custom_data"),
    ):
        if isinstance(source, dict):
            result.update(source)
    return result


def _paddle_plan_key(metadata: Dict[str, Any], items: list[Any]) -> str:
    direct = str(metadata.get("plan_key") or "").strip().lower()
    if direct in _PADDLE_PLAN_KEYS:
        return direct
    for item in items:
        item_plan_key = _paddle_item_plan_key(item)
        if item_plan_key in _PADDLE_PLAN_KEYS:
            return item_plan_key
    return direct


def _paddle_product_code(metadata: Dict[str, Any], items: list[Any]) -> str:
    direct = str(metadata.get("product_code") or "").strip().lower()
    if direct:
        return direct
    plan_key = str(metadata.get("plan_key") or "").strip().lower()
    if plan_key in _PADDLE_PLAN_KEYS:
        return f"{plan_key}_monthly"
    for item in items:
        item_metadata = _paddle_item_metadata(item)
        product_code = str(item_metadata.get("product_code") or "").strip().lower()
        if product_code:
            return product_code
        item_plan_key = _paddle_item_plan_key(item)
        if item_plan_key in _PADDLE_PLAN_KEYS:
            return f"{item_plan_key}_monthly"
    return ""


def _paddle_product_id(metadata: Dict[str, Any], items: list[Any]) -> str:
    direct = str(
        metadata.get("provider_product_id")
        or metadata.get("product_id")
        or ""
    ).strip()
    if direct:
        return direct
    for item in items:
        item_metadata = _paddle_item_metadata(item)
        product_id = str(
            item_metadata.get("provider_product_id")
            or item_metadata.get("product_id")
            or ""
        ).strip()
        if product_id:
            return product_id
        if isinstance(item, dict):
            price = item.get("price") if isinstance(item.get("price"), dict) else {}
            product = price.get("product") if isinstance(price.get("product"), dict) else {}
            product_id = str(product.get("id") or price.get("product_id") or "").strip()
            if product_id:
                return product_id
    return ""


def _paddle_quantity_for_plan_key(items: list[Any], plan_key: str) -> int:
    total = 0
    for item in items:
        if _paddle_item_plan_key(item) != plan_key:
            continue
        if isinstance(item, dict):
            try:
                total += int(item.get("quantity") or 0)
            except (TypeError, ValueError):
                pass
    return max(0, total)


def _paddle_item_plan_key(item: Any) -> str:
    metadata = _paddle_item_metadata(item)
    return str(metadata.get("plan_key") or "").strip().lower()


def _paddle_item_metadata(item: Any) -> Dict[str, Any]:
    if not isinstance(item, dict):
        return {}
    result: Dict[str, Any] = {}
    for source in (
        item.get("metadata"),
        item.get("custom_data"),
    ):
        if isinstance(source, dict):
            result.update(source)
    item_product = item.get("product") if isinstance(item.get("product"), dict) else {}
    for source in (
        item_product.get("custom_data"),
    ):
        if isinstance(source, dict):
            result.update(source)
    price = item.get("price") if isinstance(item.get("price"), dict) else {}
    product = price.get("product") if isinstance(price.get("product"), dict) else {}
    for source in (
        price.get("custom_data"),
        product.get("custom_data"),
    ):
        if isinstance(source, dict):
            result.update(source)
    return result


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
