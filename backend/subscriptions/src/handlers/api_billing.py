from __future__ import annotations

import hashlib
import uuid
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.events import (
    build_event_record,
    normalize_mobile_verify,
    parse_json_body,
)
from common.models import free_entitlement
from common.providers import checkout_url, choose_web_provider, portal_url
from common.repository import BillingRepository
from common import config

repo = BillingRepository()


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    rc = event.get("requestContext") or {}
    http = rc.get("http") or {}
    m = http.get("method") or event.get("httpMethod") or ""
    return str(m).upper()


def _provider_event_id(prefix: str, payload: Dict[str, Any]) -> str:
    raw = str(payload).encode("utf-8")
    digest = hashlib.sha1(raw).hexdigest()
    return f"{prefix}-{digest[:20]}"


def _persist_event(record: Dict[str, Any]) -> bool:
    is_new = repo.put_billing_event_if_new(record)
    if is_new:
        repo.enqueue_projection(record["event_id"])
    return is_new


def _handle_checkout(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    region_code = str(body.get("region_code") or "").upper()
    provider = choose_web_provider(region_code)
    session_id = str(uuid.uuid4())

    payload = {
        **body,
        "session_id": session_id,
        "region_code": region_code,
        "provider": provider,
    }

    record = build_event_record(
        provider=provider,
        provider_event_id=f"checkout-{session_id}",
        event_type="checkout_session_created",
        user_id=user_id,
        payload=payload,
        normalized={
            "provider": provider,
            "management_channel": provider,
        },
    )
    _persist_event(record)

    return json_response(
        200,
        {
            "provider": provider,
            "session_id": session_id,
            "checkout_url": checkout_url(provider, session_id),
        },
    )


def _handle_mobile_verify(event: Dict[str, Any], user_id: str, provider: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    normalized = normalize_mobile_verify(provider, body)

    provider_event_id = _provider_event_id(f"verify-{provider}", body)
    record = build_event_record(
        provider=provider,
        provider_event_id=provider_event_id,
        event_type="mobile_verify",
        user_id=user_id,
        payload=body,
        normalized=normalized,
    )
    inserted = _persist_event(record)

    return json_response(
        200,
        {
            "accepted": inserted,
            "provider": provider,
            "event_id": record["event_id"],
        },
    )


def _handle_restore(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    provider = str(body.get("provider") or "unknown")
    record = build_event_record(
        provider=provider,
        provider_event_id=f"restore-{uuid.uuid4()}",
        event_type="restore_requested",
        user_id=user_id,
        payload=body,
        normalized={},
    )
    inserted = _persist_event(record)

    return json_response(
        200,
        {
            "accepted": inserted,
            "event_id": record["event_id"],
            "provider": provider,
        },
    )


def _handle_portal_url(user_id: str) -> Dict[str, Any]:
    entitlement = repo.get_entitlement(user_id)
    if not entitlement:
        entitlement = free_entitlement(
            user_id=user_id,
            allow_studio_tier=config.ALLOW_STUDIO_TIER,
        ).to_dict()
    provider = str(entitlement.get("source_provider") or "unknown")
    return json_response(
        200,
        {
            "provider": provider,
            "url": portal_url(provider),
        },
    )


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    user_id = extract_user_id_from_event(event)
    if not user_id:
        return unauthorized()

    path = _path(event)
    method = _method(event)

    if method == "POST" and path.endswith("/v1/billing/web/checkout-session"):
        return _handle_checkout(event, user_id)
    if method == "POST" and path.endswith("/v1/billing/mobile/apple/verify"):
        return _handle_mobile_verify(event, user_id, provider="apple")
    if method == "POST" and path.endswith("/v1/billing/mobile/google/verify"):
        return _handle_mobile_verify(event, user_id, provider="google")
    if method == "POST" and path.endswith("/v1/billing/restore"):
        return _handle_restore(event, user_id)
    if method == "GET" and path.endswith("/v1/billing/portal-url"):
        return _handle_portal_url(user_id)

    return json_response(404, {"error": "Not found"})
