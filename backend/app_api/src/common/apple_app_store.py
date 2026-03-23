from __future__ import annotations

import base64
import json
import urllib.error
import urllib.request
from typing import Any, Dict, Optional

from . import config
from .provider_support import (
    ProviderVerificationError,
    assert_user_link_available,
    datetime_to_iso,
    first_present,
    maybe_link_customer,
    parse_datetime,
    resolve_tier_for_product,
    utc_now,
)
from .repository import BillingRepository

_APPLE_RECEIPT_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt"
_APPLE_RECEIPT_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt"
_APPLE_SANDBOX = "SANDBOX"
_APPLE_PRODUCTION = "PRODUCTION"
_verifier_cache: Dict[str, Any] = {}


def verify_apple_purchase(
    repo: BillingRepository,
    *,
    transaction_payload: str,
    expected_user_id: str = "",
    client_product_id: str = "",
    client_app_account_token: str = "",
) -> Dict[str, Any]:
    payload = (transaction_payload or "").strip()
    if not payload:
        raise ProviderVerificationError("Apple transaction payload is required.")

    if payload.count(".") == 2:
        return _verify_apple_signed_transaction(
            repo,
            signed_transaction=payload,
            expected_user_id=expected_user_id,
            client_product_id=client_product_id,
            client_app_account_token=client_app_account_token,
        )

    return _verify_apple_receipt(
        repo,
        receipt_data=payload,
        expected_user_id=expected_user_id,
        client_product_id=client_product_id,
    )


def verify_apple_notification(
    repo: BillingRepository,
    *,
    signed_payload: str,
) -> Dict[str, Any]:
    payload = (signed_payload or "").strip()
    if not payload:
        raise ProviderVerificationError("Apple signedPayload is required.")

    environment = _resolve_signed_environment(payload)
    verifier = _signed_data_verifier(environment)

    try:
        notification = verifier.verify_and_decode_notification(payload)
    except Exception as exc:
        raise ProviderVerificationError(
            f"Apple notification verification failed: {exc}",
            status_code=401,
        ) from exc

    data = _field(notification, "data") or {}
    signed_transaction = _field(data, "signedTransactionInfo") or ""
    signed_renewal = _field(data, "signedRenewalInfo") or ""

    transaction = None
    if signed_transaction:
        transaction = verifier.verify_and_decode_signed_transaction(signed_transaction)

    renewal = None
    if signed_renewal:
        renewal = verifier.verify_and_decode_renewal_info(signed_renewal)

    original_transaction_id = str(
        first_present(
            _field(transaction, "originalTransactionId"),
            _field(renewal, "originalTransactionId"),
        )
        or ""
    ).strip()
    transaction_id = str(
        first_present(
            _field(transaction, "transactionId"),
            original_transaction_id,
        )
        or ""
    ).strip()
    product_id = str(
        first_present(
            _field(transaction, "productId"),
            _field(renewal, "productId"),
        )
        or ""
    ).strip()
    if not product_id:
        raise ProviderVerificationError("Apple notification did not include a productId.", status_code=202)

    account_token = str(_field(transaction, "appAccountToken") or "").strip()
    existing_link = (
        repo.get_customer_link("apple", f"subscription:{original_transaction_id}")
        if original_transaction_id
        else None
    ) or {}
    user_id = assert_user_link_available(
        resolved_user_id=account_token,
        existing_link_user_id=str(existing_link.get("user_id") or "").strip(),
        provider="Apple",
    )

    tier = resolve_tier_for_product(repo, "apple", product_id)
    notification_type = str(_field(notification, "notificationType") or "").strip().upper()
    subtype = str(_field(notification, "subtype") or "").strip().upper()
    expires_at = datetime_to_iso(
        first_present(
            _field(transaction, "expiresDate"),
            _field(renewal, "gracePeriodExpiresDate"),
        )
    )
    status = _normalize_apple_status(
        notification_type=notification_type,
        subtype=subtype,
        expires_at=expires_at,
        revocation_date=_field(transaction, "revocationDate"),
    )

    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"subscription:{original_transaction_id}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )
    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"account:{account_token}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )

    notification_uuid = str(_field(notification, "notificationUUID") or "").strip()
    return {
        "provider_event_id": notification_uuid or f"apple:{original_transaction_id}:{notification_type}",
        "user_id": user_id,
        "provider_payload": _to_plain_dict(notification),
        "normalized": {
            "provider": "apple",
            "subscription_id": original_transaction_id or transaction_id,
            "tier": tier,
            "status": status,
            "effective_at": first_present(
                datetime_to_iso(_field(transaction, "purchaseDate")),
                datetime_to_iso(_field(notification, "signedDate")),
                utc_now().isoformat(),
            ),
            "expires_at": expires_at,
            "source_occurred_at": first_present(
                datetime_to_iso(_field(notification, "signedDate")),
                datetime_to_iso(_field(transaction, "signedDate")),
                datetime_to_iso(_field(transaction, "purchaseDate")),
            ),
            "management_channel": "apple",
            "product_id": product_id,
        },
    }


def _verify_apple_signed_transaction(
    repo: BillingRepository,
    *,
    signed_transaction: str,
    expected_user_id: str,
    client_product_id: str,
    client_app_account_token: str,
) -> Dict[str, Any]:
    environment = _resolve_signed_environment(signed_transaction)
    verifier = _signed_data_verifier(environment)

    try:
        transaction = verifier.verify_and_decode_signed_transaction(signed_transaction)
    except Exception as exc:
        raise ProviderVerificationError(
            f"Apple signed transaction verification failed: {exc}",
            status_code=401,
        ) from exc

    product_id = str(
        first_present(
            _field(transaction, "productId"),
            client_product_id,
        )
        or ""
    ).strip()
    if not product_id:
        raise ProviderVerificationError("Apple transaction did not include a productId.")

    original_transaction_id = str(_field(transaction, "originalTransactionId") or "").strip()
    transaction_id = str(_field(transaction, "transactionId") or "").strip()
    account_token = str(
        first_present(
            _field(transaction, "appAccountToken"),
            client_app_account_token,
        )
        or ""
    ).strip()
    existing_link = (
        repo.get_customer_link("apple", f"subscription:{original_transaction_id}")
        if original_transaction_id
        else None
    ) or {}
    user_id = assert_user_link_available(
        resolved_user_id=account_token,
        expected_user_id=expected_user_id,
        existing_link_user_id=str(existing_link.get("user_id") or "").strip(),
        provider="Apple",
    )

    tier = resolve_tier_for_product(repo, "apple", product_id)
    expires_at = datetime_to_iso(_field(transaction, "expiresDate"))
    status = _normalize_apple_status(
        notification_type="",
        subtype="",
        expires_at=expires_at,
        revocation_date=_field(transaction, "revocationDate"),
    )

    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"subscription:{original_transaction_id}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )
    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"account:{account_token}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )
    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"transaction:{transaction_id}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )

    return {
        "provider_event_id": f"apple:{transaction_id or original_transaction_id}",
        "user_id": user_id,
        "provider_payload": _to_plain_dict(transaction),
        "normalized": {
            "provider": "apple",
            "subscription_id": original_transaction_id or transaction_id,
            "tier": tier,
            "status": status,
            "effective_at": first_present(
                datetime_to_iso(_field(transaction, "purchaseDate")),
                utc_now().isoformat(),
            ),
            "expires_at": expires_at,
            "source_occurred_at": first_present(
                datetime_to_iso(_field(transaction, "signedDate")),
                datetime_to_iso(_field(transaction, "purchaseDate")),
            ),
            "management_channel": "apple",
            "product_id": product_id,
        },
    }


def _verify_apple_receipt(
    repo: BillingRepository,
    *,
    receipt_data: str,
    expected_user_id: str,
    client_product_id: str,
) -> Dict[str, Any]:
    from .secrets import load_apple_shared_secret

    shared_secret = load_apple_shared_secret()
    payload = {
        "receipt-data": receipt_data,
        "password": shared_secret,
        "exclude-old-transactions": False,
    }
    verified = _verify_receipt_with_fallback(payload)

    receipt_info = _select_receipt_entry(verified, client_product_id)
    if not receipt_info:
        raise ProviderVerificationError("Apple receipt did not include any subscription transactions.")

    product_id = str(
        first_present(
            receipt_info.get("product_id"),
            client_product_id,
        )
        or ""
    ).strip()
    if not product_id:
        raise ProviderVerificationError("Apple receipt did not include a product_id.")

    original_transaction_id = str(receipt_info.get("original_transaction_id") or "").strip()
    transaction_id = str(receipt_info.get("transaction_id") or "").strip()
    existing_link = (
        repo.get_customer_link("apple", f"subscription:{original_transaction_id}")
        if original_transaction_id
        else None
    ) or {}
    user_id = assert_user_link_available(
        resolved_user_id="",
        expected_user_id=expected_user_id,
        existing_link_user_id=str(existing_link.get("user_id") or "").strip(),
        provider="Apple",
    )

    tier = resolve_tier_for_product(repo, "apple", product_id)
    expires_at = datetime_to_iso(receipt_info.get("expires_date_ms"))
    status = _normalize_apple_status(
        notification_type="",
        subtype="",
        expires_at=expires_at,
        revocation_date=first_present(
            receipt_info.get("cancellation_date_ms"),
            receipt_info.get("cancellation_date"),
        ),
    )

    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"subscription:{original_transaction_id}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )
    maybe_link_customer(
        repo,
        provider="apple",
        customer_key=f"transaction:{transaction_id}",
        user_id=user_id,
        attributes={"product_id": product_id},
    )

    return {
        "provider_event_id": f"apple-receipt:{transaction_id or original_transaction_id}",
        "user_id": user_id,
        "provider_payload": verified,
        "normalized": {
            "provider": "apple",
            "subscription_id": original_transaction_id or transaction_id,
            "tier": tier,
            "status": status,
            "effective_at": first_present(
                datetime_to_iso(receipt_info.get("purchase_date_ms")),
                utc_now().isoformat(),
            ),
            "expires_at": expires_at,
            "source_occurred_at": first_present(
                datetime_to_iso(receipt_info.get("purchase_date_ms")),
                datetime_to_iso(receipt_info.get("original_purchase_date_ms")),
            ),
            "management_channel": "apple",
            "product_id": product_id,
        },
    }


def _signed_data_verifier(environment: str):
    env_key = environment.upper()
    if env_key in _verifier_cache:
        return _verifier_cache[env_key]

    try:
        from appstoreserverlibrary.models.Environment import Environment
        from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier
    except ImportError as exc:
        raise ProviderVerificationError(
            f"Missing app-store-server-library dependency: {exc}",
            status_code=500,
        ) from exc

    from .secrets import load_apple_root_certificates

    bundle_id = config.APPLE_BUNDLE_ID
    if not bundle_id:
        raise ProviderVerificationError("APPLE_BUNDLE_ID is not configured.", status_code=500)

    if env_key == _APPLE_SANDBOX:
        lib_env = Environment.SANDBOX
        app_id = None
    else:
        lib_env = Environment.PRODUCTION
        app_id = config.APPLE_APP_ID

    verifier = SignedDataVerifier(
        load_apple_root_certificates(),
        config.APPLE_ENABLE_ONLINE_CHECKS,
        lib_env,
        bundle_id,
        app_id,
    )
    _verifier_cache[env_key] = verifier
    return verifier


def _verify_receipt_with_fallback(payload: Dict[str, Any]) -> Dict[str, Any]:
    production = _post_json(_APPLE_RECEIPT_PRODUCTION_URL, payload)
    status = int(production.get("status") or 0)
    if status == 21007:
        sandbox = _post_json(_APPLE_RECEIPT_SANDBOX_URL, payload)
        sandbox_status = int(sandbox.get("status") or 0)
        if sandbox_status != 0:
            raise ProviderVerificationError(f"Apple sandbox receipt verification failed ({sandbox_status}).")
        return sandbox
    if status != 0:
        raise ProviderVerificationError(f"Apple receipt verification failed ({status}).")
    return production


def _post_json(url: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=config.HTTP_TIMEOUT_SECONDS) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ProviderVerificationError(
            f"Apple verification HTTP error ({exc.code}): {body}",
            status_code=502,
        ) from exc
    if not isinstance(decoded, dict):
        raise ProviderVerificationError("Apple verification returned an invalid response.")
    return decoded


def _select_receipt_entry(payload: Dict[str, Any], client_product_id: str) -> Optional[Dict[str, Any]]:
    candidates = payload.get("latest_receipt_info")
    if not isinstance(candidates, list) or not candidates:
        receipt = payload.get("receipt") or {}
        candidates = receipt.get("in_app") if isinstance(receipt, dict) else []
    if not isinstance(candidates, list) or not candidates:
        return None

    items = [item for item in candidates if isinstance(item, dict)]
    if client_product_id:
        filtered = [item for item in items if str(item.get("product_id") or "") == client_product_id]
        if filtered:
            items = filtered

    def _sort_key(item: Dict[str, Any]) -> tuple[str, str]:
        expires = str(item.get("expires_date_ms") or "")
        purchase = str(item.get("purchase_date_ms") or "")
        return (expires, purchase)

    items.sort(key=_sort_key, reverse=True)
    return items[0] if items else None


def _resolve_signed_environment(signed_payload: str) -> str:
    payload = _decode_unverified_jws_payload(signed_payload)
    data = payload.get("data")
    if isinstance(data, dict):
        environment = str(data.get("environment") or "").strip().upper()
        if environment:
            return environment
    environment = str(payload.get("environment") or "").strip().upper()
    if environment:
        return environment
    return _APPLE_PRODUCTION


def _decode_unverified_jws_payload(signed_payload: str) -> Dict[str, Any]:
    parts = signed_payload.split(".")
    if len(parts) != 3:
        return {}
    try:
        padding = "=" * ((4 - len(parts[1]) % 4) % 4)
        decoded = base64.urlsafe_b64decode(parts[1] + padding).decode("utf-8")
        payload = json.loads(decoded)
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _normalize_apple_status(
    *,
    notification_type: str,
    subtype: str,
    expires_at: Optional[str],
    revocation_date: Any,
) -> str:
    if revocation_date:
        return "revoked"

    notif = (notification_type or "").strip().upper()
    sub = (subtype or "").strip().upper()
    if notif == "REFUND":
        return "refunded"
    if notif == "REVOKE":
        return "revoked"
    if notif == "GRACE_PERIOD_EXPIRED":
        return "past_due"
    if notif == "DID_FAIL_TO_RENEW":
        return "grace_period" if sub == "GRACE_PERIOD" else "past_due"
    if notif == "EXPIRED":
        return "expired"

    expires_dt = parse_datetime(expires_at)
    if expires_dt and expires_dt > utc_now():
        return "active"
    if expires_dt and expires_dt <= utc_now():
        return "expired"
    return "active"


def _field(obj: Any, name: str) -> Any:
    if obj is None:
        return None
    if isinstance(obj, dict):
        return obj.get(name)
    return getattr(obj, name, None)


def _to_plain_dict(obj: Any) -> Dict[str, Any]:
    if obj is None:
        return {}
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "__dict__"):
        plain: Dict[str, Any] = {}
        for key, value in vars(obj).items():
            if key.startswith("_"):
                continue
            if isinstance(value, (str, int, float, bool)) or value is None:
                plain[key] = value
            elif hasattr(value, "__dict__"):
                plain[key] = _to_plain_dict(value)
            else:
                plain[key] = str(value)
        return plain
    return {"value": str(obj)}
