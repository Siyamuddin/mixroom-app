from __future__ import annotations

import hashlib
import json
import re
import time
import urllib.error
import urllib.request
import uuid
from calendar import monthrange
from datetime import datetime, timezone
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
from common.billing_catalog import catalog_plan_by_code, infer_plan_code
from common.collaboration_repository import CollaborationRepository
from common.events import (
    RequestBodyError,
    build_event_record,
    normalize_webhook,
    parse_json_body,
    provider_event_key,
)
from common.google_play import verify_google_purchase
from common.models import (
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    free_entitlement,
    legacy_tier_for_plan_code,
    status_has_active_access,
    subscription_effective_status,
)
from common.provider_support import ProviderVerificationError
from common.provider_portals import build_management_links
from common.providers import (
    charge_toss_billing_key,
    confirm_toss_payment,
    checkout_url,
    choose_web_provider,
    delete_toss_billing_key,
    issue_toss_billing_key,
    portal_url,
)
from common.repository import BillingRepository
from common.secrets import load_provider_api_key, put_secure_parameter_string
from common import config

repo = BillingRepository()
catalog_repo = BillingCatalogRepository()
collaboration_repo = CollaborationRepository()
init_sentry("mixroom-app-api-billing")

_TOSS_KRW_AMOUNTS = {
    "starter_monthly": 6600,
    "starter_yearly": 77000,
    "producer_monthly": 29000,
    "producer_yearly": 299000,
    "studio_monthly": 149000,
    "studio_yearly": 1490000,
    "studio_seat_addon_monthly": 22000,
    "studio_seat_addon_yearly": 220000,
    "storage_1tb_addon_monthly": 15000,
    "storage_1tb_addon_yearly": 149000,
}
_TOSS_STUDIO_INCLUDED_SEATS = 5
_PLAN_RANK = {
    "free": 0,
    "starter": 10,
    "producer": 20,
    "studio": 30,
    "education": 40,
    "enterprise": 50,
}
_PADDLE_PRICE_IDS = {
    "starter_monthly": "pri_01krvsxsje1tymj05tnbz7y50r",
    "starter_yearly": "pri_01krvsyt2dyd285ytdy47e8sry",
    "producer_monthly": "pri_01krvt0hvcvhx4dtr1tdhyhp32",
    "producer_yearly": "pri_01krvt15ak2k4ck94fzhfa0mr5",
    "studio_monthly": "pri_01krvt3yjmznvz0rw8amb9j12a",
    "studio_yearly": "pri_01krvt4dn9kfz44s6dqyaedpyc",
    "studio_seat_addon_monthly": "pri_01krvt7kktn7br0044kd7strcj",
    "studio_seat_addon_yearly": "pri_01krvt8a8vhstfkv7qxyjkc1av",
}


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


def _persist_event(record: Dict[str, Any], *, enqueue_projection: bool = True) -> bool:
    is_new = repo.put_billing_event_if_new(record)
    if is_new and enqueue_projection:
        repo.enqueue_projection(record["event_id"])
    return is_new


def _parse_datetime(raw: Any) -> datetime:
    text = str(raw or "").strip()
    if text:
        try:
            return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
        except Exception:
            pass
    return datetime.now(timezone.utc)


def _add_months(value: datetime, months: int) -> datetime:
    month_index = value.month - 1 + months
    year = value.year + month_index // 12
    month = month_index % 12 + 1
    day = min(value.day, monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


def _next_period_end(product: Dict[str, Any], start: datetime | None = None) -> str:
    start_at = start or datetime.now(timezone.utc)
    interval = str(product.get("billing_interval") or "monthly").strip().lower()
    if interval == "yearly":
        return _add_months(start_at, 12).isoformat()
    return _add_months(start_at, 1).isoformat()


def _toss_amount_for_product(product: Dict[str, Any]) -> int:
    direct = product.get("price_krw") or product.get("amount_krw")
    if direct is not None:
        try:
            return int(direct)
        except (TypeError, ValueError):
            pass
    prices = product.get("prices") if isinstance(product.get("prices"), dict) else {}
    krw = prices.get("KRW") or prices.get("krw")
    if krw is not None:
        try:
            return int(krw)
        except (TypeError, ValueError):
            pass
    code = str(product.get("code") or "").strip().lower()
    amount = _TOSS_KRW_AMOUNTS.get(code)
    if not amount:
        raise RequestBodyError("No KRW Toss price is configured for this product.", status_code=409)
    return amount


def _positive_int(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


def _toss_selection_for_product(
    product: Dict[str, Any],
    body: Dict[str, Any],
) -> Dict[str, Any]:
    product_code = str(product.get("code") or "").strip().lower()
    interval = str(product.get("billing_interval") or "monthly").strip().lower()
    total_amount = _toss_amount_for_product(product)
    additional_seats = _positive_int(
        body.get("additional_seats")
        or body.get("additionalSeats")
        or body.get("studio_seat_addon_quantity")
    )
    storage_1tb_quantity = _positive_int(
        body.get("extra_storage_tb")
        or body.get("extraStorageTb")
        or body.get("storage_1tb_addon_quantity")
    )
    seat_count = None
    extra_storage_tb = 0
    if product_code.startswith("studio_"):
        seat_key = (
            "studio_seat_addon_yearly"
            if interval == "yearly"
            else "studio_seat_addon_monthly"
        )
        storage_key = (
            "storage_1tb_addon_yearly"
            if interval == "yearly"
            else "storage_1tb_addon_monthly"
        )
        total_amount += additional_seats * _TOSS_KRW_AMOUNTS[seat_key]
        total_amount += storage_1tb_quantity * _TOSS_KRW_AMOUNTS[storage_key]
        seat_count = _TOSS_STUDIO_INCLUDED_SEATS + additional_seats
        extra_storage_tb = storage_1tb_quantity
    return {
        "amount": total_amount,
        "currency": "KRW",
        "additional_seats": additional_seats,
        "storage_1tb_quantity": storage_1tb_quantity,
        "seat_count": seat_count,
        "extra_storage_tb": extra_storage_tb,
    }


def _plan_rank(plan_code: Any) -> int:
    return _PLAN_RANK.get(infer_plan_code(plan_code), 0)


def _is_upgrade(current_plan_code: Any, target_plan_code: Any) -> bool:
    return _plan_rank(target_plan_code) > _plan_rank(current_plan_code)


def _find_active_owned_subscription(
    *,
    user_id: str,
    subscription_id: str = "",
) -> Dict[str, Any]:
    candidates = [
        item
        for item in repo.list_subscriptions_for_user(user_id)
        if isinstance(item, dict)
        and status_has_active_access(subscription_effective_status(item))
    ]
    if subscription_id:
        for item in candidates:
            if str(item.get("subscription_id") or "").strip() == subscription_id:
                return item
        raise RequestBodyError("Active subscription not found.", status_code=404)

    entitlement = repo.get_entitlement(user_id) or {}
    entitlement_subscription_id = str(entitlement.get("source_subscription_id") or "").strip()
    if entitlement_subscription_id:
        for item in candidates:
            if str(item.get("subscription_id") or "").strip() == entitlement_subscription_id:
                return item

    non_team = [
        item
        for item in candidates
        if infer_plan_code(item.get("plan_code") or item.get("tier") or "")
        not in {"education", "enterprise"}
    ]
    if non_team:
        return sorted(non_team, key=lambda item: _plan_rank(item.get("plan_code")), reverse=True)[0]
    if candidates:
        return candidates[0]
    raise RequestBodyError("No active subscription found.", status_code=404)


def _catalog_provider_product(provider: str, product_code: str) -> Dict[str, Any]:
    normalized_provider = str(provider or "").strip().lower()
    normalized_product = str(product_code or "").strip().lower()
    catalog = catalog_repo.get_catalog()
    for item in catalog.get("provider_products") or []:
        if not isinstance(item, dict):
            continue
        if str(item.get("provider") or "").strip().lower() != normalized_provider:
            continue
        if str(item.get("product_code") or "").strip().lower() != normalized_product:
            continue
        if item.get("enabled") is False:
            continue
        return dict(item)
    return {}


def _paddle_price_id_for_product(product_code: str) -> str:
    normalized = str(product_code or "").strip().lower()
    provider_product = _catalog_provider_product("paddle", normalized)
    provider_product_id = str(provider_product.get("provider_product_id") or "").strip()
    if provider_product_id.startswith("pri_"):
        return provider_product_id
    return _PADDLE_PRICE_IDS.get(normalized, "")


def _paddle_items_for_product(product: Dict[str, Any], body: Dict[str, Any]) -> list[Dict[str, Any]]:
    product_code = str(product.get("code") or "").strip().lower()
    base_price_id = _paddle_price_id_for_product(product_code)
    if not base_price_id:
        raise RequestBodyError(
            "Paddle price is not configured for this product.",
            status_code=409,
        )
    items: list[Dict[str, Any]] = [{"price_id": base_price_id, "quantity": 1}]
    if product_code.startswith("studio_"):
        additional_seats = _positive_int(
            body.get("additional_seats")
            or body.get("additionalSeats")
            or body.get("studio_seat_addon_quantity")
        )
        if additional_seats > 0:
            interval = str(product.get("billing_interval") or "monthly").strip().lower()
            seat_price_id = _paddle_price_id_for_product(
                "studio_seat_addon_yearly"
                if interval == "yearly"
                else "studio_seat_addon_monthly"
            )
            if not seat_price_id:
                raise RequestBodyError(
                    "Paddle seat add-on price is not configured.",
                    status_code=409,
                )
            items.append({"price_id": seat_price_id, "quantity": additional_seats})
    return items


def _paddle_patch_subscription(subscription_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    return _paddle_subscription_request(
        subscription_id=subscription_id,
        path_suffix="",
        payload=payload,
        action="update",
    )


def _paddle_preview_subscription(subscription_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    return _paddle_subscription_request(
        subscription_id=subscription_id,
        path_suffix="/preview",
        payload=payload,
        action="preview",
    )


def _paddle_subscription_request(
    *,
    subscription_id: str,
    path_suffix: str,
    payload: Dict[str, Any],
    action: str,
) -> Dict[str, Any]:
    if not (config.PADDLE_API_KEY_PARAMETER_NAME or config.PADDLE_API_KEY_SECRET_ARN):
        raise RequestBodyError("Paddle API key is not configured.", status_code=409)
    try:
        api_key = load_provider_api_key(
            config.PADDLE_API_KEY_SECRET_ARN,
            config.PADDLE_API_KEY_PARAMETER_NAME,
        )
    except Exception as exc:
        raise RequestBodyError(f"Paddle API key is unavailable: {str(exc)[:120]}", status_code=502)
    request = urllib.request.Request(
        f"{config.PADDLE_API_BASE_URL.rstrip('/')}/subscriptions/{subscription_id}{path_suffix}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="PATCH",
    )
    try:
        with urllib.request.urlopen(request, timeout=config.HTTP_TIMEOUT_SECONDS) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RequestBodyError(
            f"Paddle subscription {action} failed ({exc.code}): {body[:300]}",
            status_code=502,
        )
    except Exception as exc:
        raise RequestBodyError(
            f"Paddle subscription {action} failed: {str(exc)[:300]}",
            status_code=502,
        )
    if not isinstance(decoded, dict):
        raise RequestBodyError(f"Paddle subscription {action} response was invalid.", status_code=502)
    return decoded


def _sync_entitlement_from_subscription(user_id: str, subscription: Dict[str, Any]) -> None:
    plan_code = infer_plan_code(subscription.get("plan_code") or subscription.get("tier") or "")
    status = subscription_effective_status(subscription)
    existing = repo.get_entitlement(user_id) or {}
    limit_overrides: Dict[str, Any] = {}
    try:
        seat_count = int(subscription.get("seat_count") or 0)
    except (TypeError, ValueError):
        seat_count = 0
    if seat_count > 0:
        limit_overrides["members"] = seat_count
    try:
        extra_storage_tb = int(subscription.get("extra_storage_tb") or 0)
    except (TypeError, ValueError):
        extra_storage_tb = 0
    if extra_storage_tb > 0:
        limit_overrides["shared_storage_gb"] = 1024 + extra_storage_tb * 1024
    repo.put_entitlement(
        {
            "user_id": user_id,
            "tier": legacy_tier_for_plan_code(plan_code),
            "status": status,
            "effective_at": subscription.get("effective_at") or existing.get("effective_at"),
            "expires_at": subscription.get("expires_at"),
            "source_provider": str(subscription.get("provider") or ""),
            "source_subscription_id": str(subscription.get("subscription_id") or ""),
            "source_customer_id": subscription.get("customer_id"),
            "billing_email": subscription.get("customer_email"),
            "payment_method": subscription.get("payment_method"),
            "capabilities": entitlement_capabilities_for_status(plan_code, status),
            "limits": entitlement_limits_for_status(plan_code, status),
            "limit_overrides": limit_overrides,
            "limits_are_overrides": bool(limit_overrides),
            "management_channel": subscription.get("management_channel") or subscription.get("provider"),
            "plan_code": plan_code,
            "product_code": subscription.get("product_code"),
            "next_billed_at": subscription.get("next_billed_at"),
            "seat_count": subscription.get("seat_count"),
            "extra_storage_tb": subscription.get("extra_storage_tb"),
            "cancel_at_period_end": bool(subscription.get("cancel_at_period_end") or False),
            "source_occurred_at": datetime.now(timezone.utc).isoformat(),
            "revision": int(existing.get("revision") or 0) + 1,
        }
    )


def _safe_secret_segment(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9/_+=.@-]", "-", str(value or "").strip())
    return cleaned[:120] or uuid.uuid4().hex


def _payment_method_from_toss_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    card = payload.get("card") if isinstance(payload.get("card"), dict) else {}
    if not card:
        method = payload.get("paymentMethod") if isinstance(payload.get("paymentMethod"), dict) else {}
        card = method.get("card") if isinstance(method.get("card"), dict) else method
    return {
        "brand": str(card.get("company") or card.get("issuerCode") or card.get("brand") or "").strip(),
        "last4": str(card.get("number") or card.get("last4") or "")[-4:],
        "exp_month": card.get("expiryMonth") or card.get("exp_month"),
        "exp_year": card.get("expiryYear") or card.get("exp_year"),
    }


def _toss_customer_key(user_id: str, body: Dict[str, Any]) -> str:
    explicit = str(body.get("customer_key") or body.get("customerKey") or "").strip()
    if explicit:
        return explicit
    digest = hashlib.sha1(user_id.encode("utf-8")).hexdigest()[:24]
    return f"mixroom_{digest}"


def _store_toss_billing_key(
    *,
    user_id: str,
    customer_key: str,
    billing_key: str,
) -> str:
    parameter_name = (
        f"{config.TOSS_BILLING_KEY_PARAMETER_PREFIX.rstrip('/')}/"
        f"{_safe_secret_segment(customer_key)}"
    )
    return put_secure_parameter_string(
        parameter_name,
        json.dumps(
            {
                "provider": "toss",
                "user_id": user_id,
                "customer_key": customer_key,
                "billing_key": billing_key,
            }
        ),
    )


def _subscription_has_toss_billing_key(subscription: Dict[str, Any]) -> bool:
    return bool(
        str(subscription.get("billing_key_parameter_name") or "").strip()
        or str(subscription.get("billing_key_secret_arn") or "").strip()
    )


def _toss_one_time_period_start(
    *,
    user_id: str,
    product: Dict[str, Any],
    approved_at: Any,
) -> datetime:
    start_at = _parse_datetime(approved_at)
    product_code = str(product.get("code") or "").strip().lower()
    plan_code = infer_plan_code(product.get("plan_code") or "")
    for subscription in repo.list_subscriptions_for_user(user_id):
        if not isinstance(subscription, dict):
            continue
        if str(subscription.get("provider") or "").strip().lower() != "toss":
            continue
        if _subscription_has_toss_billing_key(subscription):
            continue
        if not status_has_active_access(subscription_effective_status(subscription)):
            continue
        existing_product = str(subscription.get("product_code") or "").strip().lower()
        existing_plan = infer_plan_code(subscription.get("plan_code") or subscription.get("tier") or "")
        if product_code and existing_product and existing_product != product_code:
            continue
        if plan_code and existing_plan and existing_plan != plan_code:
            continue
        expires_raw = subscription.get("expires_at") or subscription.get("current_period_end")
        if not expires_raw:
            continue
        expires_at = _parse_datetime(expires_raw)
        if expires_at > start_at:
            start_at = expires_at
    return start_at


def _load_toss_billing_key_from_subscription(subscription: Dict[str, Any]) -> str:
    parameter_name = str(subscription.get("billing_key_parameter_name") or "").strip()
    secret_arn = str(subscription.get("billing_key_secret_arn") or "").strip()
    if not parameter_name and not secret_arn:
        return ""
    return load_provider_api_key(secret_arn, parameter_name)


def _toss_subscription_id(customer_key: str, product_code: str) -> str:
    return f"toss-billing:{customer_key}:{product_code}"


def _toss_checkout_order_event_id(order_id: str) -> str:
    return provider_event_key("toss", f"checkout-order-{order_id}")


def _is_yearly_product(product: Dict[str, Any]) -> bool:
    interval = str(product.get("billing_interval") or "").strip().lower()
    code = str(product.get("code") or "").strip().lower()
    return interval in {"year", "yearly", "annual"} or code.endswith("_yearly")


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
        if (
            str(product.get("type") or "").strip().lower() == "contract"
            or str(product.get("management_channel") or "").strip().lower() == "admin"
        ):
            raise RequestBodyError(
                "This plan is handled by sales. Contact sales@mixroom.ai to continue.",
                status_code=409,
            )
    if provider == "toss" and product and _is_yearly_product(product):
        provider = "paddle"

    _assert_no_conflicting_active_subscription(
        user_id=user_id,
        target_provider=provider,
        target_plan_code=str(product.get("plan_code") or ""),
    )

    toss_order: Dict[str, Any] = {}
    if provider == "toss" and product:
        selection = _toss_selection_for_product(product, body)
        toss_order = {
            "flow": "billing",
            "amount": selection["amount"],
            "currency": "KRW",
            "order_id": f"mixroom-{uuid.uuid4().hex[:24]}",
            "order_name": str(product.get("label") or product_code or "Mixroom subscription"),
            "customer_key": _toss_customer_key(user_id, body),
            "additional_seats": selection["additional_seats"],
            "storage_1tb_quantity": selection["storage_1tb_quantity"],
            "seat_count": selection["seat_count"],
            "extra_storage_tb": selection["extra_storage_tb"],
        }

    payload = {
        **body,
        "session_id": session_id,
        "region_code": region_code,
        "provider": provider,
        "product_code": product_code,
        "plan_code": str(product.get("plan_code") or ""),
        "toss": toss_order,
    }
    provider_event_id = f"checkout-{session_id}"
    if provider == "toss" and toss_order.get("order_id"):
        provider_event_id = f"checkout-order-{toss_order['order_id']}"

    record = build_event_record(
        provider=provider,
        provider_event_id=provider_event_id,
        event_type="checkout_session_created",
        user_id=user_id,
        payload=payload,
        normalized={
            "provider": provider,
            "management_channel": provider,
            "product_code": product_code,
            "plan_code": str(product.get("plan_code") or ""),
            "order_id": toss_order.get("order_id"),
            "amount": toss_order.get("amount"),
            "currency": toss_order.get("currency"),
        },
    )
    _persist_event(record, enqueue_projection=False)

    response = {
        "provider": provider,
        "session_id": session_id,
        "checkout_url": checkout_url(provider, session_id),
        "product": product,
        "support": catalog.get("support") or {},
    }
    if provider == "toss" and toss_order:
        response["toss"] = toss_order
    if provider == "paddle" and product:
        response["paddle"] = {
            "items": [
                {
                    "priceId": item["price_id"],
                    "quantity": item.get("quantity", 1),
                }
                for item in _paddle_items_for_product(product, body)
            ]
        }

    return json_response(200, response)


def _assert_no_conflicting_active_subscription(
    *,
    user_id: str,
    target_provider: str,
    target_plan_code: str = "",
) -> None:
    for subscription in repo.list_subscriptions_for_user(user_id):
        if not isinstance(subscription, dict):
            continue
        if not status_has_active_access(subscription_effective_status(subscription)):
            continue
        provider = str(subscription.get("provider") or "").strip().lower()
        if not provider or provider in {"unknown", "admin_grant"}:
            continue
        raise RequestBodyError(
            "You already have an active subscription. Manage the existing subscription instead of starting a new checkout.",
            status_code=409,
        )

    entitlement = repo.get_entitlement(user_id) or {}
    plan_code = str(entitlement.get("plan_code") or entitlement.get("tier") or "free").strip().lower()
    if plan_code in {"", "free"}:
        return
    if not status_has_active_access(subscription_effective_status(entitlement)):
        return
    source_provider = str(entitlement.get("source_provider") or "").strip().lower()
    if not source_provider or source_provider in {"unknown", "admin_grant"}:
        return
    raise RequestBodyError(
        "You already have an active subscription. Manage or cancel it before starting a new checkout.",
        status_code=409,
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
                    "plan": str(normalized.get("plan_code") or "producer"),
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


def _handle_toss_confirm(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    payment_key = str(body.get("payment_key") or body.get("paymentKey") or "").strip()
    order_id = str(body.get("order_id") or body.get("orderId") or "").strip()
    if not payment_key or not order_id:
        raise RequestBodyError("payment_key and order_id are required.")
    if not str(user_id or "").strip():
        raise RequestBodyError("Authentication is required to confirm Toss payments.", status_code=401)
    try:
        expected_amount = int(body.get("amount") or body.get("totalAmount") or 0)
    except (TypeError, ValueError):
        expected_amount = 0
    if expected_amount <= 0:
        raise RequestBodyError("amount is required.")
    prior_event = repo.get_billing_event(provider_event_key("toss", f"confirm-{payment_key}"))
    if prior_event:
        prior_user_id = str(prior_event.get("user_id") or "").strip()
        if prior_user_id and prior_user_id != user_id:
            raise RequestBodyError("Checkout order not found.", status_code=404)
        return json_response(
            409,
            {
                "accepted": False,
                "provider": "toss",
                "event_id": prior_event.get("event_id"),
                "normalized": prior_event.get("normalized") or {},
                "idempotent_replay": True,
            },
        )
    checkout_event = repo.get_billing_event(_toss_checkout_order_event_id(order_id))
    if not isinstance(checkout_event, dict) or not checkout_event:
        raise RequestBodyError("Checkout order not found.", status_code=404)
    checkout_payload = checkout_event.get("raw_payload") if isinstance(checkout_event, dict) else {}
    if not isinstance(checkout_payload, dict):
        checkout_payload = {}
    checkout_toss = checkout_payload.get("toss") if isinstance(checkout_payload.get("toss"), dict) else {}
    checkout_user_id = str((checkout_event or {}).get("user_id") or "").strip()
    if not checkout_toss:
        raise RequestBodyError("Checkout order is not a Toss payment order.", status_code=409)
    if str(checkout_toss.get("flow") or "").strip().lower() == "billing":
        raise RequestBodyError("Toss recurring checkout must be confirmed with billing-key.", status_code=409)
    if checkout_user_id != user_id:
        raise RequestBodyError("Checkout order does not belong to this account.", status_code=403)
    try:
        checkout_amount = int(checkout_toss.get("amount") or 0)
    except (TypeError, ValueError):
        checkout_amount = 0
    if checkout_amount <= 0 or expected_amount != checkout_amount:
        raise ProviderVerificationError("Toss payment amount mismatch.", status_code=409)
    product_code = str(checkout_payload.get("product_code") or "").strip().lower()
    product = catalog_repo.get_product(product_code) if product_code else {}
    if product_code and product:
        selection = {
            "amount": checkout_amount,
            "seat_count": checkout_toss.get("seat_count"),
            "extra_storage_tb": checkout_toss.get("extra_storage_tb") or 0,
        }
        configured_amount = int(selection["amount"])
        if expected_amount != configured_amount:
            raise ProviderVerificationError("Toss payment amount mismatch.", status_code=409)
    else:
        selection = {
            "seat_count": checkout_toss.get("seat_count"),
            "extra_storage_tb": checkout_toss.get("extra_storage_tb") or 0,
        }

    payment = confirm_toss_payment(payment_key, order_id, expected_amount)
    if not payment:
        raise ProviderVerificationError("Toss payment could not be confirmed.", status_code=502)
    if str(payment.get("orderId") or "").strip() != order_id:
        raise ProviderVerificationError("Toss payment order mismatch.", status_code=409)
    try:
        actual_amount = int(payment.get("totalAmount") or payment.get("amount") or 0)
    except (TypeError, ValueError):
        actual_amount = 0
    if actual_amount != expected_amount:
        raise ProviderVerificationError("Toss payment amount mismatch.", status_code=409)
    if str(payment.get("status") or "").strip().upper() != "DONE":
        raise ProviderVerificationError("Toss payment is not complete.", status_code=409)

    effective_user_id = checkout_user_id
    customer_key = str(
        payment.get("customerKey")
        or payment.get("customer_key")
        or checkout_toss.get("customer_key")
        or effective_user_id
        or order_id
    ).strip()
    checkout_customer_key = str(checkout_toss.get("customer_key") or "").strip()
    if checkout_customer_key and customer_key and checkout_customer_key != customer_key:
        raise ProviderVerificationError("Toss payment customer mismatch.", status_code=409)
    subscription_id = f"toss-payment:{order_id}"
    period_end = None
    if product and str(product.get("type") or "").strip().lower() == "subscription":
        period_start = _toss_one_time_period_start(
            user_id=effective_user_id,
            product=product,
            approved_at=payment.get("approvedAt"),
        )
        period_end = _next_period_end(product, period_start)
    payment_method = _payment_method_from_toss_payload(payment)
    customer_email = str(
        checkout_payload.get("customer_email")
        or checkout_payload.get("email")
        or payment.get("customerEmail")
        or payment.get("customer_email")
        or ""
    ).strip().lower()
    if effective_user_id and customer_key:
        repo.put_customer_link(
            "toss",
            customer_key,
            effective_user_id,
            {
                "payment_method": payment_method,
                "email": customer_email,
            },
        )
    payload = {
        "eventType": "PAYMENT_STATUS_CHANGED",
        "data": {
            **payment,
            "metadata": {
                "mixroom_user_id": effective_user_id,
                "product_code": product_code,
                "plan_code": str(checkout_payload.get("plan_code") or ""),
                "subscription_id": subscription_id,
                "seat_count": selection.get("seat_count"),
                "extra_storage_tb": selection.get("extra_storage_tb"),
                "expires_at": period_end,
                "billing_amount": expected_amount,
                "billing_currency": "KRW",
                "customer_key": customer_key,
            },
        },
    }
    normalized = normalize_webhook("toss", payload)
    record = build_event_record(
        provider="toss",
        provider_event_id=f"confirm-{payment_key}",
        event_type="toss_payment_confirmed",
        user_id=effective_user_id,
        payload=payload,
        normalized=normalized,
    )
    inserted = _persist_event(record)
    return json_response(
        200,
        {
            "accepted": inserted,
            "provider": "toss",
            "event_id": record["event_id"],
            "normalized": normalized,
            "order_name": str(
                checkout_toss.get("order_name")
                or product.get("label")
                or product_code
                or order_id
            ),
            "amount": expected_amount,
            "method": str(payment.get("method") or payment.get("paymentMethod") or ""),
        },
    )


def _handle_toss_billing_key(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    auth_key = str(body.get("auth_key") or body.get("authKey") or "").strip()
    customer_key = _toss_customer_key(user_id, body)
    if not auth_key or not customer_key:
        raise RequestBodyError("auth_key and customer_key are required.")

    issued = issue_toss_billing_key(auth_key, customer_key)
    billing_key = str(issued.get("billingKey") or issued.get("billing_key") or "").strip()
    if not billing_key:
        raise ProviderVerificationError("Toss billing key could not be issued.", status_code=502)

    billing_key_parameter_name = _store_toss_billing_key(
        user_id=user_id,
        customer_key=customer_key,
        billing_key=billing_key,
    )
    payment_method = _payment_method_from_toss_payload(issued)
    repo.put_customer_link(
        "toss",
        customer_key,
        user_id,
        {
            "billing_key_parameter_name": billing_key_parameter_name,
            "payment_method": payment_method,
            "email": str(body.get("email") or body.get("customer_email") or "").strip().lower(),
        },
    )

    product_code = str(body.get("product_code") or body.get("productCode") or "").strip().lower()
    action = str(body.get("action") or "").strip().lower()
    if action == "update_payment_method" or not product_code:
        _replace_toss_payment_method(
            user_id=user_id,
            customer_key=customer_key,
            billing_key_parameter_name=billing_key_parameter_name,
            payment_method=payment_method,
        )
        return json_response(
            200,
            {
                "accepted": True,
                "provider": "toss",
                "customer_key": customer_key,
                "payment_method": payment_method,
                "mode": "payment_method_updated",
            },
        )

    product = catalog_repo.get_product(product_code)
    if not product or not bool(product.get("enabled")):
        raise RequestBodyError("Unknown or disabled billing product.")
    if str(product.get("type") or "").strip().lower() != "subscription":
        raise RequestBodyError("Toss billing keys are only used for subscriptions.", status_code=409)

    selection = _toss_selection_for_product(product, body)
    amount = int(selection["amount"])
    order_id = str(body.get("order_id") or body.get("orderId") or "").strip()
    if not order_id:
        raise RequestBodyError("order_id is required for Toss billing checkout.")
    prior_event = repo.get_billing_event(provider_event_key("toss", f"billing-order-{order_id}"))
    if prior_event:
        return json_response(
            200,
            {
                "accepted": False,
                "provider": "toss",
                "event_id": prior_event.get("event_id"),
                "customer_key": customer_key,
                "normalized": prior_event.get("normalized") or {},
                "idempotent_replay": True,
            },
        )
    order_name = str(body.get("order_name") or body.get("orderName") or product.get("label") or product_code)
    customer_email = str(body.get("customer_email") or body.get("email") or "").strip().lower()

    payment = charge_toss_billing_key(
        billing_key,
        customer_key=customer_key,
        amount=amount,
        order_id=order_id,
        order_name=order_name,
        customer_email=customer_email,
    )
    if not payment:
        raise ProviderVerificationError("Toss billing payment could not be approved.", status_code=502)
    if str(payment.get("status") or "").strip().upper() != "DONE":
        raise ProviderVerificationError("Toss billing payment is not complete.", status_code=409)

    period_end = _next_period_end(product, _parse_datetime(payment.get("approvedAt")))
    subscription_id = _toss_subscription_id(customer_key, product_code)
    metadata = payment.get("metadata") if isinstance(payment.get("metadata"), dict) else {}
    payload = {
        "eventType": "BILLING_PAYMENT_APPROVED",
        "data": {
            **payment,
            "customerKey": customer_key,
            "metadata": {
                **metadata,
                "mixroom_user_id": user_id,
                "subscription_id": subscription_id,
                "product_code": product_code,
                "plan_code": str(product.get("plan_code") or ""),
                "next_billed_at": period_end,
                "expires_at": period_end,
                "billing_key_parameter_name": billing_key_parameter_name,
                "billing_amount": amount,
                "billing_currency": "KRW",
                "seat_count": selection.get("seat_count"),
                "extra_storage_tb": selection.get("extra_storage_tb"),
            },
        },
    }
    normalized = normalize_webhook("toss", payload)
    record = build_event_record(
        provider="toss",
        provider_event_id=f"billing-order-{order_id}",
        event_type="toss_billing_payment_approved",
        user_id=user_id,
        payload=payload,
        normalized=normalized,
    )
    inserted = _persist_event(record)
    return json_response(
        200,
        {
            "accepted": inserted,
            "provider": "toss",
            "event_id": record["event_id"],
            "customer_key": customer_key,
            "normalized": normalized,
        },
    )


def _handle_toss_subscription_update(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    entitlement = repo.get_entitlement(user_id) or {}
    if str(entitlement.get("source_provider") or "").strip().lower() != "toss":
        raise RequestBodyError("No active Toss subscription found.", status_code=404)
    subscription_id = str(entitlement.get("source_subscription_id") or "").strip()
    subscription = repo.get_subscription(subscription_id) if subscription_id else {}
    if not subscription or not status_has_active_access(subscription_effective_status(subscription)):
        raise RequestBodyError("No active Toss subscription found.", status_code=404)
    if bool(subscription.get("cancel_at_period_end") or False):
        raise RequestBodyError("Canceled subscriptions cannot be changed.", status_code=409)

    product_code = str(
        body.get("product_code")
        or body.get("productCode")
        or subscription.get("product_code")
        or ""
    ).strip().lower()
    product = catalog_repo.get_product(product_code)
    if not product or not bool(product.get("enabled")):
        raise RequestBodyError("Unknown or disabled billing product.")
    if str(product.get("type") or "").strip().lower() != "subscription":
        raise RequestBodyError("Only subscriptions can be changed.", status_code=409)

    selection = _toss_selection_for_product(product, body)
    updated = dict(subscription)
    updated["product_code"] = product_code
    updated["plan_code"] = str(product.get("plan_code") or updated.get("plan_code") or "")
    updated["billing_amount"] = int(selection["amount"])
    updated["billing_currency"] = "KRW"
    updated["seat_count"] = selection.get("seat_count")
    updated["extra_storage_tb"] = selection.get("extra_storage_tb")
    updated["updated_at"] = datetime.now(timezone.utc).isoformat()
    repo.upsert_subscription(updated)

    entitlement["product_code"] = updated.get("product_code")
    entitlement["plan_code"] = updated.get("plan_code")
    entitlement["seat_count"] = updated.get("seat_count")
    entitlement["extra_storage_tb"] = updated.get("extra_storage_tb")
    limit_overrides = (
        dict(entitlement.get("limit_overrides"))
        if isinstance(entitlement.get("limit_overrides"), dict)
        else {}
    )
    limit_overrides.pop("members", None)
    limit_overrides.pop("shared_storage_gb", None)
    if updated.get("seat_count"):
        limit_overrides["members"] = updated.get("seat_count")
    extra_storage_tb = int(updated.get("extra_storage_tb") or 0)
    if extra_storage_tb > 0:
        limit_overrides["shared_storage_gb"] = 1024 + extra_storage_tb * 1024
    entitlement["limits"] = entitlement.get("limits") or {}
    entitlement["limit_overrides"] = limit_overrides
    entitlement["limits_are_overrides"] = bool(entitlement.get("limit_overrides"))
    entitlement["revision"] = int(entitlement.get("revision") or 0) + 1
    repo.put_entitlement(entitlement)
    return json_response(
        200,
        {
            "accepted": True,
            "provider": "toss",
            "effective": "next_renewal",
            "product_code": updated.get("product_code"),
            "billing_amount": updated.get("billing_amount"),
            "seat_count": updated.get("seat_count"),
            "extra_storage_tb": updated.get("extra_storage_tb"),
            "next_billed_at": updated.get("next_billed_at"),
        },
    )


def _handle_toss_one_time_change(
    *,
    body: Dict[str, Any],
    user_id: str,
    product: Dict[str, Any],
) -> Dict[str, Any]:
    selection = _toss_selection_for_product(product, body)
    product_code = str(product.get("code") or "").strip().lower()
    toss_order = {
        "flow": "billing",
        "amount": selection["amount"],
        "currency": "KRW",
        "order_id": f"mixroom-{uuid.uuid4().hex[:24]}",
        "order_name": str(product.get("label") or product_code or "Mixroom plan change"),
        "customer_key": _toss_customer_key(user_id, body),
        "additional_seats": selection["additional_seats"],
        "storage_1tb_quantity": selection["storage_1tb_quantity"],
        "seat_count": selection["seat_count"],
        "extra_storage_tb": selection["extra_storage_tb"],
    }
    record = build_event_record(
        provider="toss",
        provider_event_id=f"checkout-order-{toss_order['order_id']}",
        event_type="subscription_change_billing_checkout_created",
        user_id=user_id,
        payload={
            **body,
            "provider": "toss",
            "product_code": product_code,
            "plan_code": str(product.get("plan_code") or ""),
            "toss": toss_order,
        },
        normalized={
            "provider": "toss",
            "management_channel": "toss",
            "product_code": product_code,
            "plan_code": str(product.get("plan_code") or ""),
            "order_id": toss_order["order_id"],
            "amount": toss_order["amount"],
            "currency": toss_order["currency"],
        },
    )
    _persist_event(record, enqueue_projection=False)
    return json_response(
        200,
        {
            "accepted": True,
            "provider": "toss",
            "checkout_required": True,
            "checkout_flow": "toss_billing",
            "effective": "after_payment_method_setup",
            "product": product,
            "toss": toss_order,
        },
    )


def _parse_usd_price_display(value: Any) -> int | None:
    text = str(value or "").strip()
    if not text.startswith("$"):
        return None
    match = re.search(r"\$([0-9][0-9,]*(?:\.[0-9]+)?)", text)
    if not match:
        return None
    try:
        return int(round(float(match.group(1).replace(",", "")) * 100))
    except (TypeError, ValueError):
        return None


def _product_price_summary(product: Dict[str, Any], preferred_currency: str = "") -> Dict[str, Any]:
    if not product:
        return {"amount": None, "currency": "", "price_formatted": ""}
    preferred = str(preferred_currency or "").strip().upper()
    if preferred == "USD":
        usd_amount = _parse_usd_price_display(product.get("price_display"))
        if usd_amount is not None:
            return {
                "amount": usd_amount,
                "currency": "USD",
                "price_formatted": _price_formatted(usd_amount, "USD"),
            }
    if product.get("price_krw") not in (None, ""):
        try:
            amount = int(product.get("price_krw") or 0)
            return {
                "amount": amount,
                "currency": "KRW",
                "price_formatted": _price_formatted(amount, "KRW"),
            }
        except (TypeError, ValueError):
            pass
    if preferred != "KRW":
        usd_amount = _parse_usd_price_display(product.get("price_display"))
    else:
        usd_amount = None
    if usd_amount is not None:
        return {
            "amount": usd_amount,
            "currency": "USD",
            "price_formatted": _price_formatted(usd_amount, "USD"),
        }
    return {"amount": None, "currency": "", "price_formatted": str(product.get("price_display") or "")}


def _subscription_price_summary(subscription: Dict[str, Any], preferred_currency: str = "") -> Dict[str, Any]:
    amount = subscription.get("billing_amount")
    currency = str(subscription.get("billing_currency") or "").strip().upper()
    preferred = str(preferred_currency or "").strip().upper()
    if amount not in (None, "") and currency and (not preferred or currency == preferred):
        return {
            "amount": amount,
            "currency": currency,
            "price_formatted": _price_formatted(amount, currency),
        }
    product_code = str(subscription.get("product_code") or "").strip().lower()
    product = catalog_repo.get_product(product_code) if product_code else {}
    if product:
        return _product_price_summary(product, preferred_currency=preferred)
    return {"amount": None, "currency": currency, "price_formatted": ""}


def _plan_change_party(
    *,
    product: Dict[str, Any] | None = None,
    subscription: Dict[str, Any] | None = None,
    preferred_currency: str = "",
) -> Dict[str, Any]:
    product = product or {}
    subscription = subscription or {}
    plan_code = infer_plan_code(
        product.get("plan_code") or subscription.get("plan_code") or subscription.get("tier") or ""
    )
    catalog = catalog_repo.get_catalog()
    plan = catalog_plan_by_code(plan_code, catalog=catalog)
    price = (
        _subscription_price_summary(subscription, preferred_currency=preferred_currency)
        if subscription
        else _product_price_summary(product, preferred_currency=preferred_currency)
    )
    return {
        "plan_code": plan_code,
        "plan_name": str(plan.get("label") or plan_code.title()),
        "product_code": str(product.get("code") or subscription.get("product_code") or ""),
        "product_name": str(product.get("label") or subscription.get("plan_label") or plan.get("label") or ""),
        "billing_cycle": str(product.get("billing_interval") or _billing_cycle_for_product_code(subscription) or ""),
        "amount": price.get("amount"),
        "currency": price.get("currency") or "",
        "price_formatted": price.get("price_formatted") or "",
        "next_billed_at": subscription.get("next_billed_at") or subscription.get("next_billing_at"),
        "current_period_end": subscription.get("expires_at") or subscription.get("current_period_end") or subscription.get("next_billed_at"),
        "seat_count": subscription.get("seat_count"),
        "extra_storage_tb": subscription.get("extra_storage_tb") or 0,
    }


def _paddle_transaction_money(value: Any) -> Dict[str, Any]:
    if not isinstance(value, dict):
        return {"amount": None, "currency": "", "price_formatted": ""}
    details = value.get("details") if isinstance(value.get("details"), dict) else {}
    totals = details.get("totals") if isinstance(details.get("totals"), dict) else {}
    amount = (
        totals.get("total")
        or totals.get("grand_total")
        or value.get("amount")
        or value.get("total")
    )
    currency = (
        value.get("currency_code")
        or value.get("currency")
        or details.get("currency_code")
        or totals.get("currency_code")
        or totals.get("currency")
        or ""
    )
    try:
        numeric_amount = int(amount) if amount not in (None, "") else None
    except (TypeError, ValueError):
        numeric_amount = None
    safe_currency = str(currency or "").strip().upper()
    return {
        "amount": numeric_amount,
        "currency": safe_currency,
        "price_formatted": _price_formatted(numeric_amount, safe_currency),
    }


def _paddle_change_payload(
    *,
    body: Dict[str, Any],
    user_id: str,
    subscription: Dict[str, Any],
    product: Dict[str, Any],
) -> tuple[Dict[str, Any], str, str, str]:
    target_plan = infer_plan_code(product.get("plan_code") or "")
    current_plan = infer_plan_code(subscription.get("plan_code") or subscription.get("tier") or "")
    proration_mode = (
        str(body.get("proration_billing_mode") or body.get("prorationBillingMode") or "").strip()
        or ("prorated_immediately" if _is_upgrade(current_plan, target_plan) else "do_not_bill")
    )
    return (
        {
            "proration_billing_mode": proration_mode,
            "items": _paddle_items_for_product(product, body),
            "custom_data": {
                "mixroom_user_id": user_id,
                "product_code": str(product.get("code") or ""),
                "plan_key": target_plan,
            },
            "on_payment_failure": "prevent_change",
        },
        current_plan,
        target_plan,
        proration_mode,
    )


def _preview_common(
    *,
    provider: str,
    subscription: Dict[str, Any],
    product: Dict[str, Any],
    effective: str,
    proration_mode: str = "",
    checkout_required: bool = False,
    amount_due_now: Dict[str, Any] | None = None,
    next_transaction: Dict[str, Any] | None = None,
    provider_preview: Dict[str, Any] | None = None,
    preferred_currency: str = "",
) -> Dict[str, Any]:
    current_plan = infer_plan_code(subscription.get("plan_code") or subscription.get("tier") or "")
    target_plan = infer_plan_code(product.get("plan_code") or "")
    current = _plan_change_party(subscription=subscription, preferred_currency=preferred_currency)
    target = _plan_change_party(product=product, preferred_currency=preferred_currency)
    if not target.get("price_formatted") and next_transaction and next_transaction.get("price_formatted"):
        target["price_formatted"] = next_transaction.get("price_formatted")
        target["amount"] = next_transaction.get("amount")
        target["currency"] = next_transaction.get("currency")
    return {
        "preview": True,
        "provider": provider,
        "checkout_required": checkout_required,
        "effective": effective,
        "change_type": "upgrade" if _is_upgrade(current_plan, target_plan) else "change",
        "subscription_id": str(subscription.get("subscription_id") or ""),
        "current": current,
        "target": target,
        "amount_due_now": amount_due_now or {"amount": 0, "currency": target.get("currency") or current.get("currency") or "", "price_formatted": _price_formatted(0, target.get("currency") or current.get("currency") or "")},
        "next_transaction": next_transaction or {
            "amount": target.get("amount"),
            "currency": target.get("currency"),
            "price_formatted": target.get("price_formatted"),
            "billed_at": subscription.get("next_billed_at") or subscription.get("next_billing_at"),
        },
        "proration_billing_mode": proration_mode,
        "provider_preview": provider_preview or {},
    }


def _handle_paddle_subscription_change_preview(
    *,
    body: Dict[str, Any],
    user_id: str,
    subscription: Dict[str, Any],
    product: Dict[str, Any],
) -> Dict[str, Any]:
    subscription_id = str(subscription.get("subscription_id") or "").strip()
    if not subscription_id:
        raise RequestBodyError("Paddle subscription id is missing.", status_code=409)
    if bool(subscription.get("cancel_at_period_end") or False):
        raise RequestBodyError("Canceled subscriptions cannot be changed.", status_code=409)

    payload, _current_plan, _target_plan, proration_mode = _paddle_change_payload(
        body=body,
        user_id=user_id,
        subscription=subscription,
        product=product,
    )
    provider_response = _paddle_preview_subscription(subscription_id, payload)
    data = provider_response.get("data") if isinstance(provider_response.get("data"), dict) else provider_response
    immediate = _paddle_transaction_money(data.get("immediate_transaction"))
    next_tx = _paddle_transaction_money(data.get("next_transaction"))
    preview_currency = str(
        next_tx.get("currency")
        or immediate.get("currency")
        or subscription.get("billing_currency")
        or "USD"
    ).strip().upper()
    next_tx["billed_at"] = (
        (data.get("next_transaction") or {}).get("billed_at")
        if isinstance(data.get("next_transaction"), dict)
        else None
    ) or subscription.get("next_billed_at")
    preview = _preview_common(
        provider="paddle",
        subscription=subscription,
        product=product,
        effective="immediate" if proration_mode.endswith("_immediately") else "after_confirmation",
        proration_mode=proration_mode,
        checkout_required=False,
        amount_due_now=immediate,
        next_transaction=next_tx,
        provider_preview={
            "update_summary": data.get("update_summary") if isinstance(data.get("update_summary"), dict) else {},
        },
        preferred_currency=preview_currency,
    )
    if str(product.get("code") or "").startswith("studio_"):
        preview["target"]["seat_count"] = _TOSS_STUDIO_INCLUDED_SEATS + _positive_int(
            body.get("additional_seats")
            or body.get("additionalSeats")
            or body.get("studio_seat_addon_quantity")
        )
        preview["target"]["extra_storage_tb"] = _positive_int(
            body.get("extra_storage_tb")
            or body.get("extraStorageTb")
            or body.get("storage_1tb_addon_quantity")
        )
        if next_tx.get("price_formatted"):
            preview["target"]["amount"] = next_tx.get("amount")
            preview["target"]["currency"] = next_tx.get("currency")
            preview["target"]["price_formatted"] = next_tx.get("price_formatted")
    return json_response(200, preview)


def _handle_toss_subscription_change_preview(
    *,
    body: Dict[str, Any],
    subscription: Dict[str, Any],
    product: Dict[str, Any],
    checkout_required: bool,
) -> Dict[str, Any]:
    selection = _toss_selection_for_product(product, body)
    target = _product_price_summary(product)
    amount = int(selection["amount"])
    next_transaction = {
        "amount": amount,
        "currency": "KRW",
        "price_formatted": _price_formatted(amount, "KRW"),
        "billed_at": subscription.get("next_billed_at") or subscription.get("next_billing_at"),
    }
    preview = _preview_common(
        provider="toss",
        subscription=subscription,
        product={**product, "price_krw": amount},
        effective="after_payment_method_setup" if checkout_required else "next_renewal",
        checkout_required=checkout_required,
        amount_due_now=next_transaction if checkout_required else {"amount": 0, "currency": "KRW", "price_formatted": _price_formatted(0, "KRW")},
        next_transaction=next_transaction,
        preferred_currency="KRW",
    )
    if checkout_required:
        preview["checkout_flow"] = "toss_billing"
    preview["target"]["amount"] = amount
    preview["target"]["currency"] = "KRW"
    preview["target"]["price_formatted"] = _price_formatted(amount, "KRW") or target.get("price_formatted")
    preview["target"]["seat_count"] = selection.get("seat_count")
    preview["target"]["extra_storage_tb"] = selection.get("extra_storage_tb")
    return json_response(200, preview)


def _handle_paddle_subscription_change(
    *,
    body: Dict[str, Any],
    user_id: str,
    subscription: Dict[str, Any],
    product: Dict[str, Any],
) -> Dict[str, Any]:
    subscription_id = str(subscription.get("subscription_id") or "").strip()
    if not subscription_id:
        raise RequestBodyError("Paddle subscription id is missing.", status_code=409)
    if bool(subscription.get("cancel_at_period_end") or False):
        raise RequestBodyError("Canceled subscriptions cannot be changed.", status_code=409)

    payload, _current_plan, target_plan, proration_mode = _paddle_change_payload(
        body=body,
        user_id=user_id,
        subscription=subscription,
        product=product,
    )
    provider_response = _paddle_patch_subscription(subscription_id, payload)
    data = provider_response.get("data") if isinstance(provider_response.get("data"), dict) else provider_response
    updated = dict(subscription)
    updated["product_code"] = str(product.get("code") or "")
    updated["plan_code"] = target_plan
    updated["tier"] = legacy_tier_for_plan_code(target_plan)
    updated["status"] = str(data.get("status") or updated.get("status") or "active")
    updated["next_billed_at"] = data.get("next_billed_at") or updated.get("next_billed_at")
    updated["expires_at"] = data.get("ends_at") or updated.get("expires_at")
    updated["management_channel"] = "web"
    updated["updated_at"] = datetime.now(timezone.utc).isoformat()
    if str(product.get("code") or "").startswith("studio_"):
        updated["seat_count"] = _TOSS_STUDIO_INCLUDED_SEATS + _positive_int(
            body.get("additional_seats")
            or body.get("additionalSeats")
            or body.get("studio_seat_addon_quantity")
        )
        updated["extra_storage_tb"] = _positive_int(
            body.get("extra_storage_tb")
            or body.get("extraStorageTb")
            or body.get("storage_1tb_addon_quantity")
        )
    else:
        updated.pop("seat_count", None)
        updated.pop("extra_storage_tb", None)
    repo.upsert_subscription(updated)
    _sync_entitlement_from_subscription(user_id, updated)

    return json_response(
        200,
        {
            "accepted": True,
            "provider": "paddle",
            "effective": "immediate",
            "product_code": updated.get("product_code"),
            "plan_code": updated.get("plan_code"),
            "proration_billing_mode": proration_mode,
            "next_billed_at": updated.get("next_billed_at"),
            "subscription": _billing_subscription_item(updated),
        },
    )


def _web_subscription_change_request(
    event: Dict[str, Any],
    user_id: str,
) -> tuple[Dict[str, Any], Dict[str, Any], Dict[str, Any], str]:
    body = parse_json_body(event)
    product_code = str(body.get("product_code") or body.get("productCode") or "").strip().lower()
    if not product_code:
        raise RequestBodyError("product_code is required.")
    product = catalog_repo.get_product(product_code)
    if not product or not bool(product.get("enabled")):
        raise RequestBodyError("Unknown or disabled billing product.")
    if str(product.get("type") or "").strip().lower() != "subscription":
        raise RequestBodyError("Only subscriptions can be changed.", status_code=409)
    if str(product.get("management_channel") or "").strip().lower() == "admin":
        raise RequestBodyError(
            "This plan is handled by sales. Contact sales@mixroom.ai to continue.",
            status_code=409,
        )

    subscription = _find_active_owned_subscription(
        user_id=user_id,
        subscription_id=str(body.get("subscription_id") or body.get("subscriptionId") or "").strip(),
    )
    provider = str(subscription.get("provider") or "").strip().lower()
    return body, product, subscription, provider


def _handle_web_subscription_change_preview(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body, product, subscription, provider = _web_subscription_change_request(event, user_id)
    if provider == "paddle":
        return _handle_paddle_subscription_change_preview(
            body=body,
            user_id=user_id,
            subscription=subscription,
            product=product,
        )
    if provider == "toss":
        if _subscription_has_toss_billing_key(subscription):
            return _handle_toss_subscription_change_preview(
                body=body,
                subscription=subscription,
                product=product,
                checkout_required=False,
            )
        return _handle_toss_subscription_change_preview(
            body=body,
            subscription=subscription,
            product=product,
            checkout_required=True,
        )
    if provider in {"apple", "google"}:
        raise RequestBodyError(
            "This subscription is managed by the app store. Change it in the store subscription settings.",
            status_code=409,
        )
    raise RequestBodyError("This subscription provider cannot be changed on web.", status_code=409)


def _handle_web_subscription_change(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body, product, subscription, provider = _web_subscription_change_request(event, user_id)
    if provider == "paddle":
        return _handle_paddle_subscription_change(
            body=body,
            user_id=user_id,
            subscription=subscription,
            product=product,
        )
    if provider == "toss":
        if _subscription_has_toss_billing_key(subscription):
            return _handle_toss_subscription_update(event, user_id)
        return _handle_toss_one_time_change(body=body, user_id=user_id, product=product)
    if provider in {"apple", "google"}:
        raise RequestBodyError(
            "This subscription is managed by the app store. Change it in the store subscription settings.",
            status_code=409,
        )
    raise RequestBodyError("This subscription provider cannot be changed on web.", status_code=409)


def _replace_toss_payment_method(
    *,
    user_id: str,
    customer_key: str,
    billing_key_parameter_name: str,
    payment_method: Dict[str, Any],
) -> None:
    entitlement = repo.get_entitlement(user_id) or {}
    subscription_id = str(entitlement.get("source_subscription_id") or "").strip()
    if not subscription_id:
        return
    subscription = repo.get_subscription(subscription_id)
    if not subscription or str(subscription.get("provider") or "").strip().lower() != "toss":
        return
    subscription["customer_id"] = customer_key
    subscription["billing_key_parameter_name"] = billing_key_parameter_name
    subscription.pop("billing_key_secret_arn", None)
    subscription["payment_method"] = payment_method
    repo.upsert_subscription(subscription)
    entitlement["source_customer_id"] = customer_key
    entitlement["payment_method"] = payment_method
    repo.put_entitlement(entitlement)


def _handle_toss_cancel(event: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    body = parse_json_body(event)
    entitlement = repo.get_entitlement(user_id) or {}
    requested_subscription_id = str(body.get("subscription_id") or body.get("subscriptionId") or "").strip()
    subscription_id = requested_subscription_id or str(entitlement.get("source_subscription_id") or "").strip()
    subscription = repo.get_subscription(subscription_id) if subscription_id else {}
    if not subscription or str(subscription.get("provider") or "").strip().lower() != "toss":
        raise RequestBodyError("No active Toss subscription found.", status_code=404)
    if str(subscription.get("user_id") or "").strip() != user_id:
        raise RequestBodyError("No active Toss subscription found.", status_code=404)

    billing_key = _load_toss_billing_key_from_subscription(subscription)
    if billing_key:
        try:
            delete_toss_billing_key(billing_key)
        except Exception:
            pass

    now_iso = datetime.now(timezone.utc).isoformat()
    cancel_effective_at = str(subscription.get("next_billed_at") or subscription.get("expires_at") or now_iso)
    subscription["cancel_at_period_end"] = True
    subscription["expires_at"] = cancel_effective_at
    subscription["updated_at"] = now_iso
    repo.upsert_subscription(subscription)
    if str(entitlement.get("source_subscription_id") or "").strip() == subscription_id:
        entitlement["cancel_at_period_end"] = True
        entitlement["expires_at"] = cancel_effective_at
        repo.put_entitlement(entitlement)
    return json_response(
        200,
        {
            "accepted": True,
            "provider": "toss",
            "cancel_at_period_end": True,
            "expires_at": cancel_effective_at,
        },
    )


def _handle_portal_url(user_id: str) -> Dict[str, Any]:
    entitlement = _current_entitlement(user_id)
    portal = _billing_portal_payload(entitlement)
    return json_response(200, portal)


def _current_entitlement(user_id: str) -> Dict[str, Any]:
    entitlement = repo.get_entitlement(user_id)
    if entitlement:
        return entitlement
    return free_entitlement(
        user_id=user_id,
    ).to_dict()


def _billing_portal_payload(
    entitlement: Dict[str, Any],
    *,
    provider_links: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    provider = str(entitlement.get("source_provider") or entitlement.get("provider") or "unknown")
    management_channel = str(entitlement.get("management_channel") or provider).strip().lower()
    normalized_provider = provider.strip().lower()
    if normalized_provider == "apple":
        label = "Manage in App Store"
        manage_in_app = True
    elif normalized_provider == "google":
        label = "Manage in Play Store"
        manage_in_app = True
    elif normalized_provider in {"paddle", "toss"} or management_channel == "web":
        label = "Manage on web"
        manage_in_app = False
    elif management_channel == "admin":
        label = "Contact sales"
        manage_in_app = False
    else:
        label = "Manage subscription"
        manage_in_app = False
    links = provider_links.get("links") if isinstance(provider_links, dict) else {}
    if not isinstance(links, dict):
        links = {}
    url = str(
        links.get("overview")
        or links.get("subscription")
        or links.get("update_payment_method")
        or ""
    ).strip()
    if not url and normalized_provider in {"apple", "google"}:
        url = portal_url(provider)
    elif not url and normalized_provider == "paddle" and bool((provider_links or {}).get("configured")):
        url = portal_url(provider)
    return {
        "provider": provider,
        "management_channel": management_channel,
        "manage_in_app": manage_in_app,
        "label": label,
        "url": url,
        "configured": bool((provider_links or {}).get("configured")),
        "reason": str((provider_links or {}).get("reason") or ""),
    }


def _first_customer_link(user_id: str, provider: str) -> Dict[str, Any]:
    try:
        links = repo.list_customer_links_for_user(user_id)
    except Exception:
        return {}
    normalized_provider = provider.strip().lower()
    for link in links:
        if str(link.get("provider") or "").strip().lower() == normalized_provider:
            return link
    return {}


def _safe_payment_method_display(entitlement: Dict[str, Any]) -> Dict[str, Any] | None:
    payment_method = entitlement.get("payment_method")
    if not isinstance(payment_method, dict):
        return None
    display = {
        "brand": str(payment_method.get("brand") or "").strip(),
        "last4": str(payment_method.get("last4") or "").strip(),
        "exp_month": payment_method.get("exp_month"),
        "exp_year": payment_method.get("exp_year"),
    }
    if not any(str(value or "").strip() for value in display.values()):
        return None
    return display


def _handle_billing_me(user_id: str) -> Dict[str, Any]:
    entitlement = _current_entitlement(user_id)
    provider = str(entitlement.get("source_provider") or "unknown")
    customer_link = _first_customer_link(user_id, provider)
    customer_id = str(
        entitlement.get("source_customer_id")
        or customer_link.get("customer_key")
        or ""
    ).strip()
    subscription_id = str(entitlement.get("source_subscription_id") or "").strip()
    subscription = repo.get_subscription(subscription_id) if subscription_id else {}
    provider_links = build_management_links(
        provider=provider,
        customer_id=customer_id,
        subscription_id=subscription_id,
    )
    normalized_provider = provider.strip().lower()
    if normalized_provider == "toss":
        if not _subscription_has_toss_billing_key(subscription if isinstance(subscription, dict) else {}):
            provider_links = {"configured": False, "links": {}, "reason": "toss_one_time_payment"}
        else:
            provider_links = {"configured": True, "links": {}, "reason": ""}
    portal = _billing_portal_payload(entitlement, provider_links=provider_links)
    links = provider_links.get("links") if isinstance(provider_links.get("links"), dict) else {}
    payment_provider_ids = {
        "customer_id": customer_id,
        "subscription_id": subscription_id,
    }
    if normalized_provider == "paddle":
        payment_provider_ids["paddle_customer_id"] = customer_id
        payment_provider_ids["paddle_subscription_id"] = subscription_id
    elif normalized_provider == "toss":
        payment_provider_ids["toss_customer_key"] = customer_id
        payment_provider_ids["toss_subscription_id"] = subscription_id
    elif normalized_provider == "apple":
        payment_provider_ids["apple_original_transaction_id"] = subscription_id
    elif normalized_provider == "google":
        payment_provider_ids["google_purchase_token"] = subscription_id

    return json_response(
        200,
        {
            "user_id": user_id,
            "provider": provider,
            "management_channel": str(entitlement.get("management_channel") or provider),
            "plan": str(entitlement.get("plan_code") or entitlement.get("tier") or "free"),
            "plan_code": str(entitlement.get("plan_code") or entitlement.get("tier") or "free"),
            "status": str(entitlement.get("status") or "active"),
            "product_code": str(entitlement.get("product_code") or ""),
            "next_billed_at": entitlement.get("next_billed_at"),
            "next_billing_at": entitlement.get("next_billed_at"),
            "next_billing_date": entitlement.get("next_billed_at"),
            "expires_at": entitlement.get("expires_at"),
            "cancel_at_period_end": bool(entitlement.get("cancel_at_period_end") or False),
            "seat_count": entitlement.get("seat_count"),
            "extra_storage_tb": entitlement.get("extra_storage_tb") or 0,
            "billing_email": str(
                entitlement.get("billing_email")
                or customer_link.get("email")
                or ""
            ),
            "one_time_checkout_url": str(
                (subscription if isinstance(subscription, dict) else {}).get("one_time_checkout_url")
                or (subscription if isinstance(subscription, dict) else {}).get("checkout_url")
                or ""
            ).strip(),
            "payment_method": _safe_payment_method_display(entitlement),
            "customer_key": customer_id,
            "subscription_id": subscription_id,
            "provider_ids": payment_provider_ids,
            "manage": portal,
            "manage_url": portal.get("url") or "",
            "update_payment_method_url": str(links.get("update_payment_method") or ""),
            "cancel_subscription_url": str(links.get("cancel_subscription") or ""),
            "invoices_url": str(links.get("overview") or portal.get("url") or ""),
            "provider_management": {
                "configured": bool(provider_links.get("configured")),
                "reason": str(provider_links.get("reason") or ""),
            },
        },
    )


def _billing_links_for_subscription(subscription: Dict[str, Any]) -> Dict[str, Any]:
    provider = str(subscription.get("provider") or "").strip()
    normalized_provider = provider.strip().lower()
    if normalized_provider in {"apple", "google"}:
        return {
            "manage_url": portal_url(normalized_provider),
            "update_payment_method_url": "",
            "cancel_subscription_url": "",
            "invoices_url": "",
            "provider_management": {
                "configured": True,
                "reason": "",
            },
        }
    if normalized_provider == "toss":
        if _subscription_has_toss_billing_key(subscription):
            return {
                "manage_url": "",
                "update_payment_method_url": "",
                "cancel_subscription_url": "",
                "invoices_url": "",
                "provider_management": {
                    "configured": True,
                    "reason": "",
                },
            }
        return {
            "manage_url": "",
            "update_payment_method_url": "",
            "cancel_subscription_url": "",
            "invoices_url": "",
            "provider_management": {
                "configured": False,
                "reason": "toss_one_time_payment",
            },
        }
    customer_id = str(subscription.get("customer_id") or "").strip()
    subscription_id = str(subscription.get("subscription_id") or "").strip()
    provider_links = build_management_links(
        provider=provider,
        customer_id=customer_id,
        subscription_id=subscription_id,
    )
    links = provider_links.get("links") if isinstance(provider_links.get("links"), dict) else {}
    portal = _billing_portal_payload(subscription, provider_links=provider_links)
    manage_url = str(portal.get("url") or "").strip()
    update_url = str(links.get("update_payment_method") or "").strip()
    cancel_url = str(links.get("cancel_subscription") or "").strip()
    invoices_url = str(links.get("overview") or manage_url or "").strip()
    return {
        "manage_url": manage_url,
        "update_payment_method_url": update_url,
        "cancel_subscription_url": cancel_url,
        "invoices_url": invoices_url,
        "provider_management": {
            "configured": bool(provider_links.get("configured")),
            "reason": str(provider_links.get("reason") or ""),
        },
    }


def _billing_cycle_for_product_code(subscription: Dict[str, Any]) -> str:
    raw = str(
        subscription.get("billing_cycle")
        or subscription.get("billing_interval")
        or subscription.get("product_code")
        or subscription.get("product_id")
        or ""
    ).strip().lower()
    if "year" in raw or "annual" in raw:
        return "yearly"
    if "month" in raw:
        return "monthly"
    return ""


def _price_formatted(amount: Any, currency: str) -> str:
    safe_currency = str(currency or "").strip().upper()
    if amount in (None, "") or not safe_currency:
        return ""
    try:
        numeric = int(amount)
    except (TypeError, ValueError):
        return ""
    if safe_currency == "KRW":
        return f"₩{numeric:,}"
    if safe_currency == "USD":
        return f"${numeric / 100:.2f}"
    return f"{numeric} {safe_currency}"


def _billing_user_profile_summary(user_id: Any) -> Dict[str, str]:
    safe_user_id = str(user_id or "").strip()
    if not safe_user_id:
        return {}
    try:
        profile = repo.get_user_profile(safe_user_id) or {}
    except Exception:
        profile = {}
    return {
        "user_id": safe_user_id,
        "username": str(profile.get("username") or "").strip(),
        "display_name": str(profile.get("display_name") or "").strip(),
    }


def _organization_admin_profiles(organization_id: str) -> list[Dict[str, str]]:
    safe_organization_id = str(organization_id or "").strip()
    if not safe_organization_id:
        return []
    try:
        memberships = collaboration_repo.list_memberships(organization_id=safe_organization_id)
    except Exception:
        return []
    if not isinstance(memberships, list):
        return []
    if not isinstance(memberships, (list, tuple)):
        return []
    profiles: list[Dict[str, str]] = []
    seen: set[str] = set()
    for membership in memberships:
        if str(membership.get("status") or "").strip().lower() != "active":
            continue
        role = str(membership.get("role") or "").strip().lower()
        if role not in {"owner", "admin", "manager", "teacher"}:
            continue
        user_id = str(membership.get("user_id") or "").strip()
        if not user_id or user_id.startswith("invite:") or user_id in seen:
            continue
        profile = _billing_user_profile_summary(user_id)
        if profile:
            profiles.append({**profile, "role": role})
            seen.add(user_id)
    return profiles


def _billing_subscription_item(subscription: Dict[str, Any]) -> Dict[str, Any]:
    plan_code = infer_plan_code(subscription.get("plan_code") or subscription.get("tier") or "")
    catalog = catalog_repo.get_catalog()
    plan = catalog_plan_by_code(plan_code, catalog=catalog)
    payment_method = _safe_payment_method_display(subscription)
    amount = subscription.get("billing_amount")
    currency = str(subscription.get("billing_currency") or "").strip().upper()
    one_time_checkout_url = str(
        subscription.get("one_time_checkout_url")
        or subscription.get("oneTimeCheckoutUrl")
        or subscription.get("checkout_url")
        or subscription.get("checkoutUrl")
        or ""
    ).strip()
    item = {
        "subscription_id": str(subscription.get("subscription_id") or ""),
        "provider": str(subscription.get("provider") or ""),
        "plan_code": plan_code,
        "plan_name": str(plan.get("label") or plan_code.title()),
        "plan_label": str(plan.get("label") or plan_code.title()),
        "plan_group": str(plan.get("group") or "individual"),
        "status": subscription_effective_status(subscription),
        "product_code": str(subscription.get("product_code") or ""),
        "next_billed_at": subscription.get("next_billed_at"),
        "next_billing_at": subscription.get("next_billed_at"),
        "current_period_end": subscription.get("expires_at") or subscription.get("next_billed_at"),
        "expires_at": subscription.get("expires_at"),
        "cancel_at_period_end": bool(subscription.get("cancel_at_period_end") or False),
        "seat_count": subscription.get("seat_count"),
        "extra_storage_tb": subscription.get("extra_storage_tb") or 0,
        "amount": amount,
        "currency": currency,
        "price_formatted": _price_formatted(amount, currency),
        "billing_cycle": _billing_cycle_for_product_code(subscription),
        "billing_email": str(subscription.get("customer_email") or ""),
        "one_time_checkout_url": one_time_checkout_url,
        "payment_method": payment_method,
        "card": payment_method,
        "customer_key": str(subscription.get("customer_id") or ""),
        "billing_owner": True,
        "manageable": True,
    }
    item.update(_billing_links_for_subscription(subscription))
    item["manageable"] = bool(
        item["billing_owner"]
        and (
            item.get("manage_url")
            or item.get("update_payment_method_url")
            or item.get("cancel_subscription_url")
            or item.get("invoices_url")
        )
    )
    return item


def _member_of_items(user_id: str) -> list[Dict[str, Any]]:
    try:
        snapshot = collaboration_repo.build_user_access_snapshot(user_id)
    except Exception as exc:
        capture_exception(
            exc,
            tags={"service": "subscriptions_api", "dependency": "collaboration"},
        )
        return []
    items: list[Dict[str, Any]] = []
    catalog = catalog_repo.get_catalog()
    for organization in snapshot.get("organizations") or []:
        if not isinstance(organization, dict):
            continue
        status = str(organization.get("status") or "").strip().lower()
        membership_status = str(organization.get("membership_status") or "").strip().lower()
        if membership_status != "active":
            continue
        if status not in {"active", "past_due", "locked", "suspended"}:
            continue
        plan_code = infer_plan_code(organization.get("plan_code") or "")
        plan = catalog_plan_by_code(plan_code, catalog=catalog)
        organization_id = str(organization.get("organization_id") or "")
        owner_user_id = str(organization.get("owner_user_id") or "").strip()
        items.append(
            {
                "organization_id": organization_id,
                "organization_name": str(organization.get("name") or ""),
                "plan_code": plan_code,
                "plan_name": str(plan.get("label") or plan_code.title()),
                "plan_label": str(plan.get("label") or plan_code.title()),
                "plan_group": str(plan.get("group") or "team"),
                "status": status,
                "role": str(organization.get("membership_role") or ""),
                "seat_count": organization.get("seat_limit"),
                "seats_used": organization.get("seats_used"),
                "billing_owner": False,
                "manageable": False,
                "managed_by": "team_admin",
                "owner_profile": _billing_user_profile_summary(owner_user_id),
                "admin_profiles": _organization_admin_profiles(organization_id),
            }
        )
    return items


def _handle_billing_subscriptions(user_id: str) -> Dict[str, Any]:
    subscriptions = [
        item
        for item in repo.list_subscriptions_for_user(user_id)
        if isinstance(item, dict)
    ]
    owned = [_billing_subscription_item(item) for item in subscriptions]
    personal = [
        item
        for item in owned
        if str(item.get("plan_group") or "").strip().lower() not in {"team", "enterprise", "education"}
    ]
    team = [
        item
        for item in owned
        if str(item.get("plan_group") or "").strip().lower() in {"team", "enterprise", "education"}
    ]
    member_of = _member_of_items(user_id)
    return json_response(
        200,
        {
            "user_id": user_id,
            "personal": personal,
            "team": team,
            "member_of": member_of,
            "all": owned,
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
        if method == "POST" and path.endswith("/v1/billing/web/toss/confirm"):
            return _finalize(_handle_toss_confirm(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/web/subscription/change/preview"):
            return _finalize(_handle_web_subscription_change_preview(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/web/subscription/change"):
            return _finalize(_handle_web_subscription_change(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/web/toss/billing-key"):
            return _finalize(_handle_toss_billing_key(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/web/toss/subscription"):
            return _finalize(_handle_toss_subscription_update(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/web/toss/cancel"):
            return _finalize(_handle_toss_cancel(event, user_id))
        if method == "POST" and path.endswith("/v1/billing/mobile/apple/verify"):
            return _finalize(_handle_mobile_verify(event, user_id, provider="apple"))
        if method == "POST" and path.endswith("/v1/billing/mobile/google/verify"):
            return _finalize(_handle_mobile_verify(event, user_id, provider="google"))
        if method == "POST" and path.endswith("/v1/billing/restore"):
            return _finalize(_handle_restore(event, user_id))
        if method == "GET" and path.endswith("/v1/billing/me"):
            return _finalize(_handle_billing_me(user_id))
        if method == "GET" and path.endswith("/v1/billing/subscriptions"):
            return _finalize(_handle_billing_subscriptions(user_id))
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
