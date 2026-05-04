from __future__ import annotations

import hashlib
import time
import uuid
from typing import Any, Dict

from common.analytics import (
    analytics_enabled_from_body,
    build_event_properties,
    capture_event,
    client_context_from_body,
)
from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.apple_app_store import verify_apple_purchase
from common.billing_catalog_repository import BillingCatalogRepository
from common.events import RequestBodyError, build_event_record, parse_json_body
from common.google_play import verify_google_purchase
from common.models import free_entitlement
from common.provider_support import ProviderVerificationError
from common.providers import checkout_url, choose_web_provider, portal_url
from common.repository import BillingRepository
from common import config

repo = BillingRepository()
catalog_repo = BillingCatalogRepository()
init_sentry("mixroom-app-api-billing")


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
    product_code = str(body.get("product_code") or "").strip().lower()
    catalog = catalog_repo.get_catalog()
    product = {}
    if product_code:
        product = catalog_repo.get_product(product_code)
        if not product or not bool(product.get("enabled")):
            raise RequestBodyError("Unknown or disabled billing product.")

    payload = {
        **body,
        "session_id": session_id,
        "region_code": region_code,
        "provider": provider,
        "product_code": product_code,
        "plan_code": str(product.get("plan_code") or ""),
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
            "product_code": product_code,
            "plan_code": str(product.get("plan_code") or ""),
        },
    )
    _persist_event(record)

    return json_response(
        200,
        {
            "provider": provider,
            "session_id": session_id,
            "checkout_url": checkout_url(provider, session_id),
            "product": product,
            "support": catalog.get("support") or {},
        },
    )


def _handle_mobile_verify(event: Dict[str, Any], user_id: str, provider: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    analytics_enabled = analytics_enabled_from_body(body)
    client_context = client_context_from_body(body)
    if provider == "apple":
        verified = verify_apple_purchase(
            repo,
            transaction_payload=str(body.get("transaction_jws") or body.get("receipt_data") or ""),
            expected_user_id=user_id,
            client_product_id=str(body.get("product_id") or ""),
            client_app_account_token=str(body.get("app_account_token") or ""),
        )
    elif provider == "google":
        verified = verify_google_purchase(
            repo,
            purchase_token=str(body.get("purchase_token") or ""),
            package_name=str(body.get("package_name") or config.GOOGLE_PLAY_PACKAGE_NAME),
            expected_user_id=user_id,
            client_product_id=str(body.get("product_id") or ""),
            client_account_id=str(body.get("obfuscated_account_id") or ""),
        )
    else:
        raise ProviderVerificationError(f"Unsupported mobile billing provider: {provider}")

    provider_event_id = str(
        verified.get("provider_event_id")
        or _provider_event_id(f"verify-{provider}", body)
    )
    record = build_event_record(
        provider=provider,
        provider_event_id=provider_event_id,
        event_type="mobile_verify",
        user_id=str(verified.get("user_id") or user_id),
        payload=verified.get("provider_payload") if isinstance(verified.get("provider_payload"), dict) else body,
        normalized=verified.get("normalized") if isinstance(verified.get("normalized"), dict) else {},
    )
    inserted = _persist_event(record)
    normalized = record.get("normalized") if isinstance(record.get("normalized"), dict) else {}
    price_raw = body.get("price")
    currency_code = str(body.get("currency_code") or "").strip()
    billing_cycle = str(body.get("billing_cycle") or "").strip()
    price = None
    if isinstance(price_raw, (int, float)):
        price = f"{price_raw:.2f}" if currency_code else str(price_raw)
    elif isinstance(price_raw, str) and price_raw.strip():
        price = price_raw.strip()
    if price and currency_code:
        price = f"{price} {currency_code}"
    if inserted:
        capture_event(
            "subscription_started",
            distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
            properties=build_event_properties(
                user_id=str(record.get("user_id") or user_id),
                client_context=client_context,
                extra={
                    "plan": str(normalized.get("tier") or "pro"),
                    "price": price,
                    "billing_cycle": billing_cycle or _infer_billing_cycle(normalized),
                    "provider": provider,
                    "product_id": normalized.get("product_id"),
                },
            ),
            enabled=analytics_enabled,
        )

    return json_response(
        200,
        {
            "accepted": inserted,
            "provider": provider,
            "event_id": record["event_id"],
            "normalized": record.get("normalized") or {},
        },
    )


def _infer_billing_cycle(normalized: Dict[str, Any]) -> str:
    haystack = " ".join(
        [
            str(normalized.get("product_id") or ""),
            str(normalized.get("base_plan_id") or ""),
            str(normalized.get("offer_id") or ""),
        ]
    ).lower()
    if "year" in haystack or "annual" in haystack:
        return "yearly"
    if "month" in haystack:
        return "monthly"
    if "week" in haystack:
        return "weekly"
    return ""


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
    started_at = time.perf_counter()
    user_id = extract_user_id_from_event(event)
    request_context = build_request_log_context(event, _context, user_id=user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not user_id:
        return _finalize(unauthorized(), error="unauthorized")

    try:
        path = _path(event)
        method = _method(event)

        if method == "POST" and path.endswith("/v1/billing/web/checkout-session"):
            return _finalize(_handle_checkout(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/mobile/apple/verify"):
            return _finalize(_handle_mobile_verify(event, user_id, provider="apple"))
        if method == "POST" and path.endswith("/v1/billing/mobile/google/verify"):
            return _finalize(_handle_mobile_verify(event, user_id, provider="google"))
        if method == "POST" and path.endswith("/v1/billing/restore"):
            return _finalize(_handle_restore(event, user_id))
        if method == "GET" and path.endswith("/v1/billing/portal-url"):
            return _finalize(_handle_portal_url(user_id))

        return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
    except RequestBodyError as exc:
        return _finalize(
            json_response(exc.status_code, {"error": exc.message}),
            error="request_body_invalid",
        )
    except ProviderVerificationError as exc:
        if exc.status_code >= 500:
            capture_exception(
                exc,
                context=request_context,
                tags={"service": "subscriptions_api"},
            )
        return _finalize(
            json_response(exc.status_code, {"error": str(exc)}),
            error=str(exc),
        )
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "subscriptions_api"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
