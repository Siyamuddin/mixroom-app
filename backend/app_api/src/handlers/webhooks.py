from __future__ import annotations

import time
import uuid
from typing import Any, Dict

from common.apple_app_store import verify_apple_notification
from common.auth import json_response
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.events import (
    RequestBodyError,
    build_event_record,
    normalize_webhook,
    parse_json_body,
    provider_from_path,
)
from common.google_play import build_google_webhook_event, parse_google_rtdn_body, verify_google_webhook_request
from common.provider_support import ProviderVerificationError
from common.providers import verify_webhook_signature
from common.repository import BillingRepository

repo = BillingRepository()
init_sentry("mixroom-app-api-webhooks")


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
    started_at = time.perf_counter()
    path = _path(event)
    provider = provider_from_path(path)
    request_context = build_request_log_context(
        event,
        _context,
        user_id="",
    )

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    headers = _header_map(event)
    raw_body = str(event.get("body") or "")

    try:
        if provider == "apple":
            payload = parse_json_body(event)
            signed_payload = str(payload.get("signedPayload") or "").strip()
            verified = verify_apple_notification(repo, signed_payload=signed_payload)
            event_type = "apple_webhook"
            provider_event_id = str(verified.get("provider_event_id") or _resolve_provider_event_id(payload))
            user_id = str(verified.get("user_id") or "").strip()
            request_context["user_id"] = user_id
            provider_payload = verified.get("provider_payload") if isinstance(verified.get("provider_payload"), dict) else payload
            normalized = verified.get("normalized") if isinstance(verified.get("normalized"), dict) else {}
        elif provider == "google":
            verify_google_webhook_request(headers)
            payload = parse_google_rtdn_body(raw_body)
            verified = build_google_webhook_event(repo, payload)
            event_type = "google_rtdn"
            provider_event_id = str(verified.get("provider_event_id") or _resolve_provider_event_id(payload))
            user_id = str(verified.get("user_id") or "").strip()
            request_context["user_id"] = user_id
            provider_payload = verified.get("provider_payload") if isinstance(verified.get("provider_payload"), dict) else payload
            normalized = verified.get("normalized") if isinstance(verified.get("normalized"), dict) else {}
        else:
            payload = parse_json_body(event)
            if not verify_webhook_signature(provider, headers, raw_body):
                return _finalize(
                    json_response(401, {"error": "Invalid webhook signature"}),
                    error="invalid_webhook_signature",
                )
            event_type = str(payload.get("event_type") or "webhook_event")
            provider_event_id = _resolve_provider_event_id(payload)
            user_id = _resolve_user_id(payload)
            request_context["user_id"] = user_id
            provider_payload = payload
            normalized = normalize_webhook(provider, payload)

        record = build_event_record(
            provider=provider,
            provider_event_id=provider_event_id,
            event_type=event_type,
            user_id=user_id,
            payload=provider_payload,
            normalized=normalized,
        )

        inserted = repo.put_billing_event_if_new(record)
        if inserted:
            repo.enqueue_projection(record["event_id"])

        return _finalize(json_response(
            202,
            {
                "accepted": inserted,
                "provider": provider,
                "event_id": record["event_id"],
            },
        ))
    except RequestBodyError as exc:
        return _finalize(
            json_response(exc.status_code, {"accepted": False, "provider": provider, "error": exc.message}),
            error="request_body_invalid",
        )
    except ProviderVerificationError as exc:
        body = {
            "accepted": False,
            "provider": provider,
            "error": str(exc),
        }
        if exc.status_code >= 500:
            capture_exception(
                exc,
                context=request_context,
                tags={"service": "subscriptions_webhooks", "provider": provider},
            )
        return _finalize(json_response(exc.status_code, body), error=str(exc))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "subscriptions_webhooks", "provider": provider},
        )
        return _finalize(
            json_response(500, {"accepted": False, "provider": provider, "error": "Internal server error"}),
            error="internal_server_error",
        )
