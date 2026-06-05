from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any, Dict

from . import config
from .secrets import load_provider_api_key


def _has_paddle_api_key() -> bool:
    return bool(config.PADDLE_API_KEY_PARAMETER_NAME or config.PADDLE_API_KEY_SECRET_ARN)


def build_management_links(
    *,
    provider: str,
    customer_id: str = "",
    subscription_id: str = "",
) -> Dict[str, Any]:
    normalized_provider = str(provider or "").strip().lower()
    if normalized_provider == "paddle":
        return _build_paddle_management_links(
            customer_id=customer_id,
            subscription_id=subscription_id,
        )
    if normalized_provider == "toss":
        return _build_toss_management_links(customer_id=customer_id)
    return {"configured": False, "links": {}, "reason": "unsupported_provider"}


def _build_paddle_management_links(
    *,
    customer_id: str,
    subscription_id: str,
) -> Dict[str, Any]:
    if not customer_id:
        return {"configured": False, "links": {}, "reason": "missing_customer_id"}
    if not _has_paddle_api_key():
        return {"configured": False, "links": {}, "reason": "missing_paddle_api_key"}

    payload: Dict[str, Any] = {}
    if subscription_id:
        payload["subscription_ids"] = [subscription_id]

    try:
        api_key = load_provider_api_key(
            config.PADDLE_API_KEY_SECRET_ARN,
            config.PADDLE_API_KEY_PARAMETER_NAME,
        )
    except Exception as exc:
        return {
            "configured": False,
            "links": {},
            "reason": "paddle_api_key_unavailable",
            "details": str(exc)[:500],
        }

    data = _post_json(
        f"{config.PADDLE_API_BASE_URL.rstrip('/')}/customers/{customer_id}/portal-sessions",
        payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    if data.get("configured") is False and data.get("reason"):
        return data
    session = data.get("data") if isinstance(data.get("data"), dict) else data
    if not isinstance(session, dict):
        return {
            "configured": False,
            "links": {},
            "reason": "provider_response_invalid",
        }
    urls = session.get("urls") if isinstance(session.get("urls"), dict) else {}
    general = urls.get("general") if isinstance(urls.get("general"), dict) else {}
    links: Dict[str, str] = {
        "overview": str(general.get("overview") or "").strip(),
    }

    subscription_links = urls.get("subscriptions")
    if isinstance(subscription_links, list):
        for item in subscription_links:
            if not isinstance(item, dict):
                continue
            if subscription_id and str(item.get("id") or item.get("subscription_id") or "") not in {
                "",
                subscription_id,
            }:
                continue
            for source_key, target_key in (
                ("overview", "subscription"),
                ("update_subscription_payment_method", "update_payment_method"),
                ("update_payment_method", "update_payment_method"),
                ("cancel_subscription", "cancel_subscription"),
            ):
                value = str(item.get(source_key) or "").strip()
                if value:
                    links[target_key] = value

    return {
        "configured": True,
        "links": {key: value for key, value in links.items() if value},
        "reason": "",
    }


def _build_toss_management_links(*, customer_id: str) -> Dict[str, Any]:
    if not customer_id:
        return {"configured": False, "links": {}, "reason": "missing_customer_id"}
    return {"configured": True, "links": {}, "reason": ""}


def _post_json(url: str, payload: Dict[str, Any], *, headers: Dict[str, str]) -> Dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=config.HTTP_TIMEOUT_SECONDS) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return {
            "configured": False,
            "links": {},
            "reason": f"provider_http_error_{exc.code}",
            "details": body[:500],
        }
    except Exception as exc:
        return {
            "configured": False,
            "links": {},
            "reason": "provider_request_failed",
            "details": str(exc)[:500],
        }
    if not isinstance(decoded, dict):
        return {
            "configured": False,
            "links": {},
            "reason": "provider_response_invalid",
        }
    return decoded
