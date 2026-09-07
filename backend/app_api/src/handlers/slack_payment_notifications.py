from __future__ import annotations

import base64
import json
import os
from decimal import Decimal, InvalidOperation
from typing import Any, Dict
from urllib.parse import quote
from urllib import error, request

import boto3


_PROVIDER_LABELS = {
    "apple": "Apple App Store",
    "google": "Google Play",
    "paddle": "Paddle",
    "toss": "Toss Payments",
}
_ZERO_DECIMAL_CURRENCIES = {"CLP", "JPY", "KRW"}
_ssm_client = boto3.client("ssm")
_billing_events_table = boto3.resource("dynamodb").Table(
    os.environ.get("BILLING_EVENTS_TABLE", "billing-events")
)
_webhook_url: str | None = None
_provider_secrets: Dict[str, str] = {}


def _environment() -> str:
    return os.environ.get("ENVIRONMENT", "dev").strip() or "dev"


def _http_timeout_seconds() -> int:
    return min(int(os.environ.get("HTTP_TIMEOUT_SECONDS", "10") or "10"), 10)


def _slack_webhook_url() -> str:
    global _webhook_url
    if _webhook_url:
        return _webhook_url
    parameter_name = os.environ.get("SLACK_PAYMENT_WEBHOOK_PARAMETER_NAME", "").strip()
    if not parameter_name:
        raise ValueError("SLACK_PAYMENT_WEBHOOK_PARAMETER_NAME is not configured.")
    response = _ssm_client.get_parameter(Name=parameter_name, WithDecryption=True)
    _webhook_url = str((response.get("Parameter") or {}).get("Value") or "").strip()
    return _webhook_url


def _parameter_secret(environment_key: str) -> str:
    parameter_name = os.environ.get(environment_key, "").strip()
    if not parameter_name:
        return ""
    cached = _provider_secrets.get(parameter_name)
    if cached:
        return cached
    response = _ssm_client.get_parameter(Name=parameter_name, WithDecryption=True)
    raw = str((response.get("Parameter") or {}).get("Value") or "").strip()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw
    if isinstance(parsed, dict):
        for key in ("api_key", "secret_key", "token", "PADDLE_API_KEY"):
            value = str(parsed.get(key) or "").strip()
            if value:
                raw = value
                break
    _provider_secrets[parameter_name] = raw
    return raw


def _billing_event(event_id: str) -> Dict[str, Any]:
    if not event_id:
        return {}
    response = _billing_events_table.get_item(Key={"event_id": event_id}, ConsistentRead=True)
    item = response.get("Item") or {}
    return item if isinstance(item, dict) else {}


def _raw_data(record: Dict[str, Any]) -> Dict[str, Any]:
    raw = record.get("raw_payload") or {}
    if not isinstance(raw, dict):
        return {}
    data = raw.get("data")
    return data if isinstance(data, dict) else raw


def _is_initial_subscription_purchase(record: Dict[str, Any]) -> bool:
    event_type = str(record.get("event_type") or "").strip().lower()
    raw = record.get("raw_payload") or {}
    if not isinstance(raw, dict):
        return False

    if event_type in {"toss_payment_confirmed", "toss_billing_payment_approved"}:
        return True
    if event_type == "apple_webhook":
        return str(raw.get("notificationType") or "").strip().upper() == "SUBSCRIBED"
    if event_type == "google_rtdn":
        notification = raw.get("subscriptionNotification") or {}
        try:
            return int(notification.get("notificationType")) == 4
        except (AttributeError, TypeError, ValueError):
            return False
    if event_type == "transaction.completed":
        data = _raw_data(record)
        origin = str(data.get("origin") or "").strip().lower()
        subscription_id = str(data.get("subscription_id") or "").strip()
        return origin in {"web", "api"} and subscription_id.startswith("sub_")
    return False


def _decode_jws_payload(value: Any) -> Dict[str, Any]:
    parts = str(value or "").split(".")
    if len(parts) != 3:
        return {}
    try:
        encoded = parts[1] + ("=" * ((4 - len(parts[1]) % 4) % 4))
        decoded = json.loads(base64.urlsafe_b64decode(encoded).decode("utf-8"))
    except (ValueError, json.JSONDecodeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _money_amount(value: Any) -> tuple[Any, str]:
    if not isinstance(value, dict):
        return None, ""
    currency = str(value.get("currencyCode") or value.get("currency_code") or "").upper()
    try:
        units = Decimal(str(value.get("units") or 0))
        nanos = Decimal(str(value.get("nanos") or 0)) / Decimal(1_000_000_000)
        return units + nanos, currency
    except InvalidOperation:
        return None, currency


def _google_order(package_name: str, order_id: str) -> Dict[str, Any]:
    if not package_name or not order_id:
        return {}
    try:
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account

        raw = _parameter_secret("GOOGLE_SERVICE_ACCOUNT_PARAMETER_NAME")
        info = json.loads(raw)
        credentials = service_account.Credentials.from_service_account_info(
            info,
            scopes=["https://www.googleapis.com/auth/androidpublisher"],
        )
        session = AuthorizedSession(credentials)
        url = (
            "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
            f"{quote(package_name, safe='')}/orders/{quote(order_id, safe='')}"
        )
        response = session.get(url, timeout=_http_timeout_seconds())
        payload = response.json() if response.status_code == 200 else {}
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _paddle_address(address_id: str) -> Dict[str, Any]:
    if not address_id:
        return {}
    api_key = _parameter_secret("PADDLE_API_KEY_PARAMETER_NAME")
    if not api_key:
        return {}
    address_request = request.Request(
        f"https://api.paddle.com/addresses/{quote(address_id, safe='')}",
        headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
        method="GET",
    )
    try:
        with request.urlopen(address_request, timeout=_http_timeout_seconds()) as response:
            payload = json.loads(response.read().decode("utf-8"))
        data = payload.get("data") if isinstance(payload, dict) else None
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _enrich_purchase(detail: Dict[str, Any], record: Dict[str, Any]) -> Dict[str, Any]:
    enriched = dict(detail)
    provider = str(enriched.get("provider") or record.get("provider") or "").strip().lower()
    raw = record.get("raw_payload") or {}
    normalized = record.get("normalized") or {}
    raw = raw if isinstance(raw, dict) else {}
    normalized = normalized if isinstance(normalized, dict) else {}

    if provider == "toss":
        data = _raw_data(record)
        enriched["amount"] = data.get("totalAmount") or data.get("amount") or enriched.get("amount")
        enriched["currency"] = str(enriched.get("currency") or "KRW").upper()
        enriched["region_code"] = "KR"
    elif provider == "paddle":
        data = _raw_data(record)
        address = _paddle_address(str(data.get("address_id") or ""))
        custom_data = data.get("custom_data") if isinstance(data.get("custom_data"), dict) else {}
        enriched["region_code"] = str(
            address.get("country_code")
            or custom_data.get("region_code")
            or ""
        ).upper()
    elif provider == "apple":
        transaction = raw.get("transaction") if isinstance(raw.get("transaction"), dict) else {}
        if not transaction:
            raw_data = raw.get("data") if isinstance(raw.get("data"), dict) else {}
            transaction = _decode_jws_payload(raw_data.get("signedTransactionInfo"))
        if not transaction:
            transaction = raw
        price = transaction.get("price")
        if price not in (None, ""):
            try:
                enriched["amount"] = Decimal(str(price)) / Decimal(1000)
            except InvalidOperation:
                pass
        enriched["currency"] = str(transaction.get("currency") or enriched.get("currency") or "").upper()
        enriched["region_code"] = str(transaction.get("storefront") or "").upper()
    elif provider == "google":
        line_items = raw.get("lineItems") if isinstance(raw.get("lineItems"), list) else []
        line_item = line_items[0] if line_items and isinstance(line_items[0], dict) else {}
        order = _google_order(
            str(normalized.get("package_name") or ""),
            str(line_item.get("latestSuccessfulOrderId") or ""),
        )
        amount, currency = _money_amount(order.get("total"))
        if amount is not None:
            enriched["amount"] = amount
        if currency:
            enriched["currency"] = currency
        buyer_address = order.get("buyerAddress") if isinstance(order.get("buyerAddress"), dict) else {}
        enriched["region_code"] = str(
            buyer_address.get("countryCode")
            or buyer_address.get("country")
            or raw.get("regionCode")
            or ""
        ).upper()

    return enriched


def _safe_text(value: Any) -> str:
    return (
        str(value or "")
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def _title_case_code(value: Any, fallback: str = "Unknown") -> str:
    text = str(value or "").strip()
    if not text:
        return fallback
    return text.replace("_", " ").replace("-", " ").title()


def _format_amount(detail: Dict[str, Any]) -> str:
    amount = detail.get("amount")
    currency = str(detail.get("currency") or "").strip().upper()
    if amount in (None, ""):
        return "Not reported by provider"
    if not currency:
        return str(amount)

    try:
        numeric = Decimal(str(amount))
    except InvalidOperation:
        return f"{currency} {amount}"

    # Paddle transaction totals use the currency's lowest denomination. Toss
    # reports totalAmount in the currency's major denomination.
    if str(detail.get("provider") or "").strip().lower() == "paddle":
        exponent = 0 if currency in _ZERO_DECIMAL_CURRENCIES else 2
        numeric /= Decimal(10) ** exponent

    decimals = 0 if numeric == numeric.to_integral_value() else 2
    return f"{currency} {numeric:,.{decimals}f}"


def _build_slack_payload(detail: Dict[str, Any]) -> Dict[str, Any]:
    provider_key = str(detail.get("provider") or "").strip().lower()
    provider = _PROVIDER_LABELS.get(provider_key, _title_case_code(provider_key))
    plan = _title_case_code(detail.get("plan_code"))
    product = _title_case_code(detail.get("product_code"), "Not reported")
    amount = _format_amount(detail)
    region = str(detail.get("region_code") or "").strip().upper() or "Not reported by provider"
    email = str(detail.get("customer_email") or "").strip()
    user_id = str(detail.get("user_id") or "").strip()
    user = email or user_id or "Unknown"
    purchased_at = str(detail.get("purchased_at") or "").strip() or "Unknown"
    event_id = str(detail.get("event_id") or "").strip() or "Unknown"
    environment = _environment()

    fallback = f"New subscription payment: {provider} · {plan} · {amount}"
    return {
        "text": fallback,
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "New subscription payment", "emoji": True},
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Provider*\n{_safe_text(provider)}"},
                    {"type": "mrkdwn", "text": f"*Amount*\n{_safe_text(amount)}"},
                    {"type": "mrkdwn", "text": f"*Region*\n{_safe_text(region)}"},
                    {"type": "mrkdwn", "text": f"*Plan*\n{_safe_text(plan)}"},
                    {"type": "mrkdwn", "text": f"*Product*\n{_safe_text(product)}"},
                    {"type": "mrkdwn", "text": f"*User*\n{_safe_text(user)}"},
                    {"type": "mrkdwn", "text": f"*Paid at*\n{_safe_text(purchased_at)}"},
                ],
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Environment: `{_safe_text(environment)}` · Event: `{_safe_text(event_id)}`",
                    }
                ],
            },
        ],
    }


def _purchase_detail(record: Dict[str, Any]) -> Dict[str, Any]:
    message = ((record.get("Sns") or {}).get("Message"))
    if isinstance(message, str):
        envelope = json.loads(message)
    elif isinstance(message, dict):
        envelope = message
    else:
        envelope = record

    detail = envelope.get("detail") if isinstance(envelope, dict) else None
    if not isinstance(detail, dict):
        raise ValueError("Payment notification did not include an EventBridge detail object.")
    return detail


def _post_to_slack(payload: Dict[str, Any]) -> None:
    webhook_url = _slack_webhook_url()
    if not webhook_url.startswith("https://hooks.slack.com/services/"):
        raise ValueError("The configured Slack payment webhook URL is invalid.")

    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    slack_request = request.Request(
        webhook_url,
        data=body,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with request.urlopen(slack_request, timeout=_http_timeout_seconds()) as response:
            response_body = response.read().decode("utf-8", errors="replace").strip()
            if response.status < 200 or response.status >= 300 or response_body.lower() != "ok":
                raise RuntimeError(f"Slack rejected the payment notification ({response.status}).")
    except error.HTTPError as exc:
        raise RuntimeError(f"Slack rejected the payment notification ({exc.code}).") from exc
    except error.URLError as exc:
        raise RuntimeError("Slack payment notification could not be delivered.") from exc


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    records = event.get("Records") or []
    notified = 0
    ignored = 0
    for record in records:
        detail = _purchase_detail(record)
        billing_event = _billing_event(str(detail.get("event_id") or ""))
        if not _is_initial_subscription_purchase(billing_event):
            ignored += 1
            continue
        _post_to_slack(_build_slack_payload(_enrich_purchase(detail, billing_event)))
        notified += 1
    return {"statusCode": 200, "notified": notified, "ignored": ignored}
