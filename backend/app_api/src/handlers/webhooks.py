from __future__ import annotations

import hmac
import logging
import time
import uuid
from datetime import datetime, timezone
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
    provider_event_key,
    provider_from_path,
)
from common.google_play import build_google_webhook_event, parse_google_rtdn_body, verify_google_webhook_request
from common.provider_support import ProviderVerificationError
from common.providers import retrieve_toss_payment, verify_webhook_signature
from common.rate_limits import client_ip_from_event
from common.repository import BillingRepository
from common.secrets import load_stibee_webhook_shared_secret
from common.users import apply_user_profile_patch

repo = BillingRepository()
init_sentry("mixroom-app-api-webhooks")
_logger = logging.getLogger(__name__)


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


def _toss_payment_field(source: Dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = str(source.get(key) or "").strip()
        if value:
            return value
    return ""


def _toss_order_context(order_id: str) -> Dict[str, Any]:
    for prefix in ("checkout-order", "billing-order"):
        event = repo.get_billing_event(provider_event_key("toss", f"{prefix}-{order_id}"))
        if isinstance(event, dict) and event:
            return event
    return {}


def _trusted_toss_metadata(
    *,
    trusted_event: Dict[str, Any],
    checkout_toss: Dict[str, Any],
    payment: Dict[str, Any],
    order_id: str,
) -> Dict[str, Any]:
    raw_payload = trusted_event.get("raw_payload") if isinstance(trusted_event.get("raw_payload"), dict) else {}
    normalized = trusted_event.get("normalized") if isinstance(trusted_event.get("normalized"), dict) else {}
    raw_data = raw_payload.get("data") if isinstance(raw_payload.get("data"), dict) else {}
    raw_metadata = raw_data.get("metadata") if isinstance(raw_data.get("metadata"), dict) else {}
    user_id = str(trusted_event.get("user_id") or raw_metadata.get("mixroom_user_id") or "").strip()
    product_code = str(
        raw_payload.get("product_code")
        or raw_metadata.get("product_code")
        or normalized.get("product_code")
        or ""
    ).strip().lower()
    plan_code = str(
        raw_payload.get("plan_code")
        or raw_metadata.get("plan_code")
        or normalized.get("plan_code")
        or ""
    ).strip()
    subscription_id = str(
        raw_metadata.get("subscription_id")
        or normalized.get("subscription_id")
        or f"toss-payment:{order_id}"
    ).strip()
    amount = payment.get("totalAmount") or payment.get("amount") or raw_metadata.get("billing_amount")
    customer_key = _toss_payment_field(payment, "customerKey", "customer_key") or str(
        checkout_toss.get("customer_key") or raw_metadata.get("customer_key") or normalized.get("customer_id") or ""
    ).strip()
    return {
        "mixroom_user_id": user_id,
        "product_code": product_code,
        "plan_code": plan_code,
        "subscription_id": subscription_id,
        "seat_count": checkout_toss.get("seat_count") or raw_metadata.get("seat_count") or normalized.get("seat_count"),
        "extra_storage_tb": (
            checkout_toss.get("extra_storage_tb")
            or raw_metadata.get("extra_storage_tb")
            or normalized.get("extra_storage_tb")
            or 0
        ),
        "expires_at": raw_metadata.get("expires_at") or normalized.get("expires_at"),
        "next_billed_at": raw_metadata.get("next_billed_at") or normalized.get("next_billed_at"),
        "billing_key_parameter_name": raw_metadata.get("billing_key_parameter_name") or normalized.get("billing_key_parameter_name"),
        "billing_amount": amount,
        "billing_currency": raw_metadata.get("billing_currency") or normalized.get("billing_currency") or "KRW",
        "customer_key": customer_key,
    }


def _toss_subscription_context(payment: Dict[str, Any]) -> Dict[str, Any]:
    customer_key = _toss_payment_field(payment, "customerKey", "customer_key")
    if not customer_key:
        return {}
    link = repo.get_customer_link("toss", customer_key) or {}
    user_id = str(link.get("user_id") or "").strip()
    if not user_id:
        return {}
    try:
        actual_amount = int(payment.get("totalAmount") or payment.get("amount") or 0)
    except (TypeError, ValueError):
        actual_amount = 0
    for subscription in repo.list_subscriptions_for_user(user_id):
        if str(subscription.get("provider") or "").strip().lower() != "toss":
            continue
        if str(subscription.get("customer_id") or "").strip() != customer_key:
            continue
        try:
            expected_amount = int(subscription.get("billing_amount") or 0)
        except (TypeError, ValueError):
            expected_amount = 0
        if expected_amount and actual_amount and expected_amount != actual_amount:
            continue
        return {
            "event_id": str(subscription.get("subscription_id") or ""),
            "provider": "toss",
            "provider_event_id": str(subscription.get("subscription_id") or ""),
            "event_type": "subscription_snapshot",
            "user_id": user_id,
            "raw_payload": {
                "product_code": str(subscription.get("product_code") or "").strip().lower(),
                "plan_code": str(subscription.get("plan_code") or subscription.get("tier") or "").strip(),
                "data": {
                    "metadata": {
                        "subscription_id": str(subscription.get("subscription_id") or ""),
                        "product_code": str(subscription.get("product_code") or "").strip().lower(),
                        "plan_code": str(subscription.get("plan_code") or subscription.get("tier") or "").strip(),
                        "next_billed_at": subscription.get("next_billed_at"),
                        "expires_at": subscription.get("expires_at"),
                        "billing_key_parameter_name": subscription.get("billing_key_parameter_name"),
                        "billing_amount": actual_amount or expected_amount,
                        "billing_currency": subscription.get("billing_currency") or "KRW",
                        "customer_key": customer_key,
                        "seat_count": subscription.get("seat_count"),
                        "extra_storage_tb": subscription.get("extra_storage_tb") or 0,
                    },
                },
            },
            "normalized": {
                "subscription_id": str(subscription.get("subscription_id") or ""),
                "product_code": str(subscription.get("product_code") or "").strip().lower(),
                "plan_code": str(subscription.get("plan_code") or subscription.get("tier") or "").strip(),
                "customer_id": customer_key,
                "next_billed_at": subscription.get("next_billed_at"),
                "expires_at": subscription.get("expires_at"),
                "billing_amount": actual_amount or expected_amount,
                "billing_currency": subscription.get("billing_currency") or "KRW",
                "seat_count": subscription.get("seat_count"),
                "extra_storage_tb": subscription.get("extra_storage_tb") or 0,
            },
        }
    return {}


def _handle_toss_payment_webhook(payload: Dict[str, Any]) -> tuple[str, str, Dict[str, Any], Dict[str, Any]]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    payment_key = _toss_payment_field(data, "paymentKey", "payment_key")
    order_id = _toss_payment_field(data, "orderId", "order_id")
    if not payment_key or not order_id:
        raise ProviderVerificationError("Toss webhook paymentKey and orderId are required.", status_code=400)

    payment = retrieve_toss_payment(payment_key)
    if not payment:
        raise ProviderVerificationError("Toss payment could not be verified.", status_code=502)
    if _toss_payment_field(payment, "paymentKey", "payment_key") != payment_key:
        raise ProviderVerificationError("Toss payment key mismatch.", status_code=409)
    if _toss_payment_field(payment, "orderId", "order_id") != order_id:
        raise ProviderVerificationError("Toss payment order mismatch.", status_code=409)

    trusted_event = _toss_order_context(order_id) or _toss_subscription_context(payment)
    if not trusted_event:
        raise ProviderVerificationError("Toss checkout order not found.", status_code=404)
    trusted_payload = trusted_event.get("raw_payload") if isinstance(trusted_event.get("raw_payload"), dict) else {}
    checkout_toss = trusted_payload.get("toss") if isinstance(trusted_payload.get("toss"), dict) else {}
    try:
        expected_amount = int(checkout_toss.get("amount") or 0)
    except (TypeError, ValueError):
        expected_amount = 0
    try:
        actual_amount = int(payment.get("totalAmount") or payment.get("amount") or 0)
    except (TypeError, ValueError):
        actual_amount = 0
    if expected_amount and actual_amount != expected_amount:
        raise ProviderVerificationError("Toss payment amount mismatch.", status_code=409)

    expected_customer_key = str(checkout_toss.get("customer_key") or "").strip()
    actual_customer_key = _toss_payment_field(payment, "customerKey", "customer_key")
    if expected_customer_key and actual_customer_key and expected_customer_key != actual_customer_key:
        raise ProviderVerificationError("Toss payment customer mismatch.", status_code=409)

    provider_payload = {
        "eventType": payload.get("eventType") or payload.get("event_type") or "PAYMENT_STATUS_CHANGED",
        "createdAt": payload.get("createdAt") or payload.get("created_at"),
        "data": {
            **payment,
            "metadata": _trusted_toss_metadata(
                trusted_event=trusted_event,
                checkout_toss=checkout_toss,
                payment=payment,
                order_id=order_id,
            ),
        },
    }
    normalized = normalize_webhook("toss", provider_payload)
    provider_event_id = str(
        payload.get("eventId")
        or payload.get("event_id")
        or f"{provider_payload['eventType']}:{payment_key}:{payment.get('status') or ''}"
    )
    return provider_event_id, str(trusted_event.get("user_id") or ""), provider_payload, normalized


def _resolve_user_id(payload: Dict[str, Any], *, provider: str = "") -> str:
    for metadata in _metadata_candidates(payload):
        for key in ("mixroom_user_id", "user_id", "sub"):
            value = str(metadata.get(key) or "").strip()
            if value:
                return value

    for key in ("mixroom_user_id", "user_id", "sub"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value

    customer_key = _customer_key(payload)
    if provider and customer_key:
        link = repo.get_customer_link(provider, customer_key) or {}
        user_id = str(link.get("user_id") or "").strip()
        if user_id:
            return user_id

    email = _customer_email(payload)
    if email:
        account = repo.get_auth_account_by_email(email)
        user_id = str((account or {}).get("user_id") or "").strip()
        if user_id:
            return user_id
        profile = repo.get_user_profile_by_email(email)
        user_id = str((profile or {}).get("user_id") or "").strip()
        if user_id:
            return user_id

    return ""


def _metadata_candidates(payload: Dict[str, Any]) -> list[Dict[str, Any]]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    candidates: list[Dict[str, Any]] = []
    for source in (
        payload.get("metadata"),
        payload.get("custom_data"),
        data.get("metadata"),
        data.get("custom_data"),
    ):
        if isinstance(source, dict):
            candidates.append(source)
    return candidates


def _customer_email(payload: Dict[str, Any]) -> str:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    for container in (data.get("customer"), payload.get("customer")):
        if isinstance(container, dict):
            email = str(container.get("email") or "").strip().lower()
            if email:
                return email
    return str(
        data.get("customer_email")
        or payload.get("customer_email")
        or ""
    ).strip().lower()


def _customer_key(payload: Dict[str, Any]) -> str:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    for key in ("customer_id", "customerKey", "customer_key"):
        value = str(data.get(key) or payload.get(key) or "").strip()
        if value:
            return value
    for container in (data.get("customer"), payload.get("customer")):
        if isinstance(container, dict):
            value = str(container.get("id") or container.get("customerKey") or "").strip()
            if value:
                return value
    return ""


def _query_map(event: Dict[str, Any]) -> Dict[str, str]:
    query = event.get("queryStringParameters") or {}
    return {str(k): str(v) for k, v in query.items()}


def _stibee_shared_secret() -> str:
    if not (
        config.STIBEE_WEBHOOK_SHARED_SECRET
        or config.STIBEE_WEBHOOK_SHARED_SECRET_PARAMETER_NAME
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
    for key in ("addressBookId", "address_book_id", "listId", "list_id", "id"):
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
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                _logger.warning(
                    "Ignoring unparseable Stibee occurred_at value.",
                    extra={"stibee_timestamp_field": key},
                )
                return ""
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            else:
                parsed = parsed.astimezone(timezone.utc)
            return parsed.isoformat()
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
    failed_users = 0
    for subscriber in _stibee_subscribers(payload):
        email = _stibee_subscriber_email(subscriber)
        if not email:
            continue
        try:
            profile = repo.get_user_profile_by_email(email)
            if not isinstance(profile, dict) or not profile:
                continue
            next_profile = apply_user_profile_patch(profile, patch)
            user_id = str(next_profile.get("user_id") or "").strip()
            if not user_id:
                continue
            repo.update_user_newsletter_subscription(
                user_id,
                newsletter_opt_in=bool(next_profile.get("newsletter_opt_in")),
                newsletter_opt_in_at=next_profile.get("newsletter_opt_in_at"),
            )
            updated_user_ids.append(user_id)
        except Exception as exc:
            failed_users += 1
            capture_exception(
                exc,
                context={
                    **request_context,
                    "stibee_action": action,
                    "stibee_email_domain": email.split("@")[-1] if "@" in email else "",
                },
                tags={"service": "subscriptions_webhooks", "provider": "stibee"},
            )

    if updated_user_ids:
        request_context["user_id"] = updated_user_ids[0]

    return json_response(
        202,
        {
            "accepted": True,
            "provider": "stibee",
            "action": action,
            "updated_users": len(updated_user_ids),
            "failed_users": failed_users,
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
        elif provider == "toss":
            payload = parse_json_body(event)
            event_type = str(payload.get("eventType") or payload.get("event_type") or "toss_webhook")
            provider_event_id, user_id, provider_payload, normalized = _handle_toss_payment_webhook(payload)
            request_context["user_id"] = user_id
        else:
            payload = parse_json_body(event)
            if not verify_webhook_signature(provider, headers, raw_body):
                return _finalize(
                    json_response(401, {"error": "Invalid webhook signature"}),
                    error="invalid_webhook_signature",
                )
            event_type = str(payload.get("event_type") or "webhook_event")
            provider_event_id = _resolve_provider_event_id(payload)
            user_id = _resolve_user_id(payload, provider=provider)
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
            customer_key = _customer_key(provider_payload)
            if customer_key and user_id:
                repo.put_customer_link(
                    provider,
                    customer_key,
                    user_id,
                    {
                        "email": _customer_email(provider_payload),
                        "source_event_id": record["event_id"],
                    },
                )
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
