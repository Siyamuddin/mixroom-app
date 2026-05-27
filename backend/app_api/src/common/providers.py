from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
import urllib.error
import urllib.request
from typing import Dict

from . import config
from .models import normalize_provider
from .secrets import load_provider_api_key, load_webhook_secret


def _has_secret_ref(*values: str) -> bool:
    return any(str(value or "").strip() for value in values)


def choose_web_provider(region_code: str) -> str:
    # KR route -> Toss, all other regions -> Paddle.
    if (region_code or "").strip().upper() == "KR":
        return "toss"
    return "paddle"


def verify_webhook_signature(provider: str, headers: Dict[str, str], raw_body: str) -> bool:
    provider = normalize_provider(provider)
    if provider == "unknown":
        return False

    if provider == "paddle":
        if not _has_secret_ref(
            config.PADDLE_WEBHOOK_SECRET_PARAMETER_NAME,
            config.PADDLE_WEBHOOK_SECRET_ARN,
        ):
            return False
        signature = str(headers.get("Paddle-Signature") or headers.get("paddle-signature") or "").strip()
        if not signature:
            return False
        secret = load_webhook_secret(
            config.PADDLE_WEBHOOK_SECRET_ARN,
            config.PADDLE_WEBHOOK_SECRET_PARAMETER_NAME,
        )
        return _verify_paddle_signature(
            signature_header=signature,
            raw_body=raw_body or "",
            secret=secret,
        )

    return False


def retrieve_toss_payment(payment_key: str) -> Dict[str, object]:
    return _request_toss_payment(
        f"{config.TOSS_API_BASE_URL.rstrip('/')}/v1/payments/{payment_key}",
        method="GET",
    )


def confirm_toss_payment(payment_key: str, order_id: str, amount: int) -> Dict[str, object]:
    return _request_toss_payment(
        f"{config.TOSS_API_BASE_URL.rstrip('/')}/v1/payments/confirm",
        method="POST",
        body={
            "paymentKey": payment_key,
            "orderId": order_id,
            "amount": amount,
        },
    )


def issue_toss_billing_key(auth_key: str, customer_key: str) -> Dict[str, object]:
    return _request_toss_payment(
        f"{config.TOSS_API_BASE_URL.rstrip('/')}/v1/billing/authorizations/issue",
        method="POST",
        body={
            "authKey": auth_key,
            "customerKey": customer_key,
        },
    )


def charge_toss_billing_key(
    billing_key: str,
    *,
    customer_key: str,
    amount: int,
    order_id: str,
    order_name: str,
    customer_email: str = "",
) -> Dict[str, object]:
    body: Dict[str, object] = {
        "customerKey": customer_key,
        "amount": amount,
        "orderId": order_id,
        "orderName": order_name,
    }
    if customer_email:
        body["customerEmail"] = customer_email
    return _request_toss_payment(
        f"{config.TOSS_API_BASE_URL.rstrip('/')}/v1/billing/{billing_key}",
        method="POST",
        body=body,
    )


def delete_toss_billing_key(billing_key: str) -> Dict[str, object]:
    return _request_toss_payment(
        f"{config.TOSS_API_BASE_URL.rstrip('/')}/v1/billing/{billing_key}",
        method="DELETE",
    )


def _request_toss_payment(
    url: str,
    *,
    method: str,
    body: Dict[str, object] | None = None,
) -> Dict[str, object]:
    try:
        secret_key = load_provider_api_key(
            config.TOSS_SECRET_KEY_SECRET_ARN,
            config.TOSS_SECRET_KEY_PARAMETER_NAME,
        )
    except Exception:
        return {}
    token = base64.b64encode(f"{secret_key}:".encode("utf-8")).decode("ascii")
    payload = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=config.HTTP_TIMEOUT_SECONDS) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _verify_paddle_signature(
    *,
    signature_header: str,
    raw_body: str,
    secret: str,
    tolerance_seconds: int = 300,
) -> bool:
    parts: Dict[str, list[str]] = {}
    for segment in str(signature_header or "").split(";"):
        key, separator, value = segment.partition("=")
        if not separator:
            continue
        normalized_key = key.strip()
        normalized_value = value.strip()
        if normalized_key and normalized_value:
            parts.setdefault(normalized_key, []).append(normalized_value)

    timestamp = (parts.get("ts") or [""])[0]
    signatures = parts.get("h1") or []
    if not timestamp or not signatures:
        return False

    try:
        timestamp_seconds = int(timestamp)
    except ValueError:
        return False
    if abs(int(time.time()) - timestamp_seconds) > tolerance_seconds:
        return False

    signed_payload = f"{timestamp}:{raw_body}".encode("utf-8")
    expected = hmac.new(
        secret.encode("utf-8"),
        signed_payload,
        hashlib.sha256,
    ).hexdigest()
    return any(hmac.compare_digest(expected, candidate) for candidate in signatures)


def checkout_url(provider: str, session_id: str) -> str:
    base = config.DEFAULT_CHECKOUT_URL.rstrip("/")
    return f"{base}/{provider}/{session_id}"


def portal_url(provider: str) -> str:
    provider = normalize_provider(provider)
    if provider == "apple":
        return "https://apps.apple.com/account/subscriptions"
    if provider == "google":
        return "https://play.google.com/store/account/subscriptions"
    if provider == "paddle":
        return "https://customers.paddle.com"
    if provider == "toss":
        return "https://toss.im"
    return "https://www.mixroom.ai/account/subscription"
