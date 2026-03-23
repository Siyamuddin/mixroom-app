from __future__ import annotations

import base64
import json
from typing import Any, Dict, Optional

from . import config
from .provider_support import (
    ProviderVerificationError,
    assert_user_link_available,
    datetime_to_iso,
    first_present,
    maybe_link_customer,
    maybe_link_purchase_token,
    parse_datetime,
    resolve_tier_for_product,
    utc_now,
)
from .repository import BillingRepository

_PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
_PLAY_API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3"


def verify_google_purchase(
    repo: BillingRepository,
    *,
    purchase_token: str,
    package_name: str,
    expected_user_id: str = "",
    client_product_id: str = "",
    client_account_id: str = "",
) -> Dict[str, Any]:
    token = (purchase_token or "").strip()
    package = (package_name or config.GOOGLE_PLAY_PACKAGE_NAME).strip()
    if not token:
        raise ProviderVerificationError("Google purchase token is required.")
    if not package:
        raise ProviderVerificationError("GOOGLE_PLAY_PACKAGE_NAME is not configured.")

    payload = _fetch_subscription_purchase(package, token)
    line_item = _select_line_item(payload)
    product_id = str(
        first_present(
            line_item.get("productId"),
            client_product_id,
        )
        or ""
    ).strip()
    if not product_id:
        raise ProviderVerificationError("Google purchase did not include a product ID.")

    external_ids = payload.get("externalAccountIdentifiers") or {}
    store_account_user = str(
        first_present(
            external_ids.get("obfuscatedExternalAccountId"),
            client_account_id,
        )
        or ""
    ).strip()
    existing_link = repo.get_purchase_token("google", token) or {}
    linked_user = str(existing_link.get("user_id") or "").strip()
    user_id = assert_user_link_available(
        resolved_user_id=store_account_user,
        expected_user_id=expected_user_id,
        existing_link_user_id=linked_user,
        provider="Google Play",
    )

    tier = resolve_tier_for_product(
        repo,
        "google",
        product_id,
    )
    expires_at = datetime_to_iso(line_item.get("expiryTime"))
    status = _normalize_google_status(
        subscription_state=str(payload.get("subscriptionState") or ""),
        expires_at=expires_at,
        revoked=bool(payload.get("canceledStateContext", {}).get("systemInitiatedCancellation")),
    )

    order_id = str(payload.get("latestOrderId") or "").strip()
    subscription_id = order_id or token
    base_plan_id = str(line_item.get("basePlanId") or "").strip()
    offer_id = str(line_item.get("offerId") or "").strip()

    maybe_link_purchase_token(
        repo,
        provider="google",
        token=token,
        attributes={
            "user_id": user_id,
            "product_id": product_id,
            "subscription_id": subscription_id,
            "package_name": package,
            "base_plan_id": base_plan_id,
            "offer_id": offer_id,
        },
    )
    maybe_link_customer(
        repo,
        provider="google",
        customer_key=f"subscription:{subscription_id}",
        user_id=user_id,
        attributes={
            "product_id": product_id,
            "package_name": package,
        },
    )
    maybe_link_customer(
        repo,
        provider="google",
        customer_key=f"account:{store_account_user}",
        user_id=user_id,
        attributes={"package_name": package},
    )

    provider_event_id = (
        f"google:{subscription_id}:{status}:{expires_at or 'none'}"
    )

    return {
        "provider_event_id": provider_event_id,
        "user_id": user_id,
        "provider_payload": payload,
        "normalized": {
            "provider": "google",
            "subscription_id": subscription_id,
            "tier": tier,
            "status": status,
            "effective_at": first_present(payload.get("startTime"), utc_now().isoformat()),
            "expires_at": expires_at,
            "source_occurred_at": first_present(
                payload.get("startTime"),
                line_item.get("expiryTime"),
            ),
            "management_channel": "google",
            "product_id": product_id,
            "package_name": package,
            "base_plan_id": base_plan_id,
            "offer_id": offer_id,
        },
    }


def verify_google_webhook_request(headers: Dict[str, str]) -> None:
    if not config.GOOGLE_PUBSUB_AUDIENCE:
        return

    auth_header = headers.get("authorization") or headers.get("Authorization") or ""
    token = auth_header.replace("Bearer", "").strip()
    if not token:
        raise ProviderVerificationError("Missing Google RTDN bearer token.", status_code=401)

    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import id_token
    except ImportError as exc:
        raise ProviderVerificationError(
            f"Missing google-auth dependency: {exc}",
            status_code=500,
        ) from exc

    claims = id_token.verify_oauth2_token(
        token,
        Request(),
        audience=config.GOOGLE_PUBSUB_AUDIENCE,
    )
    email = str(claims.get("email") or "").strip().lower()
    if config.GOOGLE_PUBSUB_SERVICE_ACCOUNT_EMAIL:
        expected = config.GOOGLE_PUBSUB_SERVICE_ACCOUNT_EMAIL.strip().lower()
        if email != expected:
            raise ProviderVerificationError("Unexpected Google RTDN service account.", status_code=401)


def parse_google_rtdn_body(raw_body: str) -> Dict[str, Any]:
    try:
        envelope = json.loads(raw_body or "{}")
    except json.JSONDecodeError as exc:
        raise ProviderVerificationError("Google RTDN body is not valid JSON.") from exc

    if not isinstance(envelope, dict):
        raise ProviderVerificationError("Google RTDN body must be a JSON object.")

    message = envelope.get("message") or {}
    if not isinstance(message, dict):
        raise ProviderVerificationError("Google RTDN message wrapper is missing.")

    encoded = str(message.get("data") or "").strip()
    if not encoded:
        return envelope

    padding = "=" * ((4 - len(encoded) % 4) % 4)
    decoded = base64.urlsafe_b64decode(encoded + padding).decode("utf-8")
    payload = json.loads(decoded)
    if not isinstance(payload, dict):
        raise ProviderVerificationError("Decoded Google RTDN payload must be an object.")
    payload["_pubsub_message_id"] = str(message.get("messageId") or "").strip()
    return payload


def build_google_webhook_event(
    repo: BillingRepository,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    test_notification = payload.get("testNotification")
    if isinstance(test_notification, dict):
        raise ProviderVerificationError("Google RTDN test notification received.", status_code=202)

    subscription_notification = payload.get("subscriptionNotification") or {}
    if isinstance(subscription_notification, dict) and subscription_notification:
        purchase_token = str(subscription_notification.get("purchaseToken") or "").strip()
        package_name = str(payload.get("packageName") or config.GOOGLE_PLAY_PACKAGE_NAME).strip()
        if not purchase_token:
            raise ProviderVerificationError("Google RTDN subscription notification has no purchaseToken.")

        verified = verify_google_purchase(
            repo,
            purchase_token=purchase_token,
            package_name=package_name,
        )
        verified["provider_event_id"] = str(
            first_present(
                payload.get("_pubsub_message_id"),
                verified.get("provider_event_id"),
            )
        )
        normalized = verified.get("normalized")
        if isinstance(normalized, dict):
            normalized["source_occurred_at"] = first_present(
                payload.get("eventTimeMillis"),
                normalized.get("source_occurred_at"),
            )
        return verified

    voided_purchase = payload.get("voidedPurchaseNotification") or {}
    if isinstance(voided_purchase, dict) and voided_purchase:
        purchase_token = str(voided_purchase.get("purchaseToken") or "").strip()
        linked = repo.get_purchase_token("google", purchase_token) if purchase_token else None
        if not linked:
            raise ProviderVerificationError("Google voided purchase is not linked to any user.", status_code=202)

        product_id = str(linked.get("product_id") or "").strip()
        tier = resolve_tier_for_product(repo, "google", product_id)
        refund_type = str(voided_purchase.get("refundType") or "").strip()
        status = "refunded" if refund_type == "1" else "revoked"

        return {
            "provider_event_id": str(
                first_present(
                    payload.get("_pubsub_message_id"),
                    f"google-voided:{linked.get('subscription_id') or purchase_token}:{status}",
                )
            ),
            "user_id": str(linked.get("user_id") or "").strip(),
            "provider_payload": payload,
            "normalized": {
                "provider": "google",
                "subscription_id": str(linked.get("subscription_id") or purchase_token),
                "tier": tier,
                "status": status,
                "effective_at": utc_now().isoformat(),
                "expires_at": utc_now().isoformat(),
                "source_occurred_at": first_present(
                    payload.get("eventTimeMillis"),
                    utc_now().isoformat(),
                ),
                "management_channel": "google",
                "product_id": product_id,
                "package_name": str(linked.get("package_name") or config.GOOGLE_PLAY_PACKAGE_NAME),
            },
        }

    raise ProviderVerificationError("Unsupported Google RTDN payload.", status_code=202)


def _fetch_subscription_purchase(package_name: str, purchase_token: str) -> Dict[str, Any]:
    session = _authorized_google_session()
    url = (
        f"{_PLAY_API_ROOT}/applications/{package_name}"
        f"/purchases/subscriptionsv2/tokens/{purchase_token}"
    )
    response = session.get(url, timeout=config.HTTP_TIMEOUT_SECONDS)
    if response.status_code == 404:
        raise ProviderVerificationError("Google purchase token was not found.", status_code=404)
    if response.status_code >= 400:
        raise ProviderVerificationError(
            f"Google Play verification failed ({response.status_code}): {response.text}",
            status_code=502,
        )
    payload = response.json()
    if not isinstance(payload, dict):
        raise ProviderVerificationError("Google Play returned an invalid response.")
    return payload


def _authorized_google_session():
    try:
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account
    except ImportError as exc:
        raise ProviderVerificationError(
            f"Missing google-auth dependency: {exc}",
            status_code=500,
        ) from exc

    from .secrets import load_google_service_account_info

    info = load_google_service_account_info()
    credentials = service_account.Credentials.from_service_account_info(
        info,
        scopes=[_PLAY_SCOPE],
    )
    return AuthorizedSession(credentials)


def _select_line_item(payload: Dict[str, Any]) -> Dict[str, Any]:
    line_items = payload.get("lineItems") or []
    if not isinstance(line_items, list) or not line_items:
        raise ProviderVerificationError("Google purchase payload has no lineItems.")

    def _sort_key(item: Any) -> tuple[int, str]:
        if not isinstance(item, dict):
            return (0, "")
        expiry = datetime_to_iso(item.get("expiryTime")) or ""
        active = 1 if parse_datetime(item.get("expiryTime")) and parse_datetime(item.get("expiryTime")) > utc_now() else 0
        return (active, expiry)

    best = sorted(
        [item for item in line_items if isinstance(item, dict)],
        key=_sort_key,
        reverse=True,
    )
    if not best:
        raise ProviderVerificationError("Google purchase payload lineItems are invalid.")
    return best[0]


def _normalize_google_status(
    *,
    subscription_state: str,
    expires_at: Optional[str],
    revoked: bool,
) -> str:
    state = (subscription_state or "").strip().upper()
    expires_dt = parse_datetime(expires_at)
    has_future_expiry = expires_dt is not None and expires_dt > utc_now()

    if revoked:
        return "revoked"
    if state == "SUBSCRIPTION_STATE_ACTIVE":
        return "active"
    if state == "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
        return "grace_period"
    if state == "SUBSCRIPTION_STATE_ON_HOLD":
        return "past_due"
    if state == "SUBSCRIPTION_STATE_PAUSED":
        return "paused"
    if state == "SUBSCRIPTION_STATE_CANCELED":
        return "active" if has_future_expiry else "expired"
    if state == "SUBSCRIPTION_STATE_PENDING":
        return "past_due"
    if state == "SUBSCRIPTION_STATE_EXPIRED":
        return "expired"
    return "active" if has_future_expiry else "expired"
