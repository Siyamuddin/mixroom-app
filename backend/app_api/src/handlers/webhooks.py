from __future__ import annotations

import hmac
import time
import uuid
from typing import Any, Dict

from common import config
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
from common.rate_limits import client_ip_from_event
from common.repository import BillingRepository
from common.secrets import load_stibee_webhook_shared_secret
from common.users import apply_user_profile_patch

repo = BillingRepository()
init_sentry("mixroom-app-api-webhooks")


class StibeeWebhookVerificationError(Exception):
    def __init__(self, message: str, *, status_code: int = 401) -> None:
        super().__init__(message)
        self.status_code = status_code


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _header_map(event: Dict[str, Any]) -> Dict[str, str]:
    headers = event.get("headers") or {}
    normalized: Dict[str, str] = {}
    for key, value in headers.items():
        text_key = str(key)
        text_value = str(value)
        normalized[text_key] = text_value
        normalized[text_key.lower()] = text_value
    return normalized


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


def _query_map(event: Dict[str, Any]) -> Dict[str, str]:
    query = event.get("queryStringParameters") or {}
    return {str(k): str(v) for k, v in query.items()}


def _stibee_shared_secret() -> str:
    if not (
        config.STIBEE_WEBHOOK_SHARED_SECRET
        or config.STIBEE_WEBHOOK_SHARED_SECRET_ARN
    ):
        return ""
    return load_stibee_webhook_shared_secret()


def _stibee_secret_candidate(event: Dict[str, Any], headers: Dict[str, str]) -> str:
    query = _query_map(event)
    for key in ("secret", "token", "webhook_secret"):
        value = str(query.get(key) or "").strip()
        if value:
            return value

    for key in ("x-stibee-secret", "x-webhook-secret", "x-mixroom-webhook-secret"):
        value = str(headers.get(key) or headers.get(key.title()) or "").strip()
        if value:
            return value

    authorization = str(headers.get("authorization") or headers.get("Authorization") or "").strip()
    if authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return authorization


def _verify_stibee_webhook_request(event: Dict[str, Any], headers: Dict[str, str]) -> None:
    source_ip = client_ip_from_event(event)
    allowed_ips = set(config.STIBEE_WEBHOOK_ALLOWED_IPS)
    if allowed_ips and source_ip not in allowed_ips:
        raise StibeeWebhookVerificationError("Invalid webhook source IP.")

    configured_secret = _stibee_shared_secret()
    if not configured_secret:
        return

    provided_secret = _stibee_secret_candidate(event, headers)
    if not provided_secret or not hmac.compare_digest(provided_secret, configured_secret):
        raise StibeeWebhookVerificationError("Invalid Stibee webhook secret.")


def _stibee_list_id(payload: Dict[str, Any]) -> str:
    for key in ("addressBookId", "address_book_id", "listId", "list_id"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value
    return ""


def _stibee_action(payload: Dict[str, Any]) -> str:
    return str(payload.get("action") or "").strip().upper()


def _stibee_occurred_at(payload: Dict[str, Any]) -> str:
    for key in ("occurredAt", "occurred_at", "eventOccurredAt", "updatedAt", "updated_at"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value
    return ""


def _stibee_subscribers(payload: Dict[str, Any]) -> list[Dict[str, Any]]:
    subscribers = payload.get("subscribers")
    if isinstance(subscribers, dict):
        return [subscribers]
    if isinstance(subscribers, list):
        return [item for item in subscribers if isinstance(item, dict)]
    return []


def _stibee_subscriber_email(subscriber: Dict[str, Any]) -> str:
    for key in ("email", "subscriberEmail", "subscriber_email"):
        value = str(subscriber.get(key) or "").strip().lower()
        if value:
            return value
    return ""


def _stibee_subscription_patch(
    *,
    action: str,
    occurred_at: str,
) -> Dict[str, Any] | None:
    if action == "UNSUBSCRIBED":
        return {
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
        }
    if action in {"SUBSCRIBED", "RESUBSCRIBED"}:
        return {
            "newsletter_opt_in": True,
            "newsletter_opt_in_at": occurred_at or None,
        }
    return None


def _handle_stibee_webhook(
    event: Dict[str, Any],
    headers: Dict[str, str],
    request_context: Dict[str, Any],
) -> Dict[str, Any]:
    _verify_stibee_webhook_request(event, headers)
    payload = parse_json_body(event)
    action = _stibee_action(payload)
    patch = _stibee_subscription_patch(
        action=action,
        occurred_at=_stibee_occurred_at(payload),
    )
    if patch is None:
        return json_response(
            202,
            {
                "accepted": True,
                "provider": "stibee",
                "ignored": True,
                "reason": "unsupported_action",
                "action": action or "unknown",
            },
        )

    list_id = _stibee_list_id(payload)
    configured_newsletter_list_id = str(config.STIBEE_NEWSLETTER_LIST_ID or "").strip()
    if list_id and configured_newsletter_list_id and list_id != configured_newsletter_list_id:
        return json_response(
            202,
            {
                "accepted": True,
                "provider": "stibee",
                "ignored": True,
                "reason": "non_newsletter_list",
                "list_id": list_id,
                "action": action,
            },
        )

    updated_user_ids: list[str] = []
    for subscriber in _stibee_subscribers(payload):
        email = _stibee_subscriber_email(subscriber)
        if not email:
            continue
        profile = repo.get_user_profile_by_email(email)
        if not isinstance(profile, dict) or not profile:
            continue
        next_profile = apply_user_profile_patch(profile, patch)
        previous_username_lc = str(profile.get("username_lc") or "").strip().lower() or None
        repo.upsert_user_profile(
            next_profile,
            previous_username_lc=previous_username_lc,
        )
        user_id = str(next_profile.get("user_id") or "").strip()
        if user_id:
            updated_user_ids.append(user_id)

    if updated_user_ids:
        request_context["user_id"] = updated_user_ids[0]

    return json_response(
        202,
        {
            "accepted": True,
            "provider": "stibee",
            "action": action,
            "updated_users": len(updated_user_ids),
        },
    )


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
        if provider == "stibee":
            return _finalize(
                _handle_stibee_webhook(event, headers, request_context)
            )
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
    except StibeeWebhookVerificationError as exc:
        return _finalize(
            json_response(
                exc.status_code,
                {
                    "accepted": False,
                    "provider": provider,
                    "error": str(exc),
                },
            ),
            error=str(exc),
        )
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
