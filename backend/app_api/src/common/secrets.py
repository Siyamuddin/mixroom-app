from __future__ import annotations

import json
import time
from typing import Any, Dict, List, Tuple

import boto3

from . import config

_secrets_client = boto3.client("secretsmanager")
_secret_cache: Dict[str, Tuple[float, str]] = {}


def _cache_ttl_seconds() -> int:
    return max(30, config.SECRET_CACHE_TTL_SECONDS)


def get_secret_string(secret_arn: str) -> str:
    arn = (secret_arn or "").strip()
    if not arn:
        raise ValueError("Missing secret ARN.")

    cached = _secret_cache.get(arn)
    now = time.time()
    if cached and now - cached[0] < _cache_ttl_seconds():
        return cached[1]

    response = _secrets_client.get_secret_value(SecretId=arn)
    raw = response.get("SecretString")
    if raw is None:
        binary = response.get("SecretBinary")
        if binary is None:
            raise ValueError(f"Secret {arn} has no string or binary payload.")
        if isinstance(binary, bytes):
            raw = binary.decode("utf-8")
        else:
            raw = str(binary)

    value = str(raw)
    _secret_cache[arn] = (now, value)
    return value


def get_secret_json(secret_arn: str) -> Dict[str, Any]:
    raw = get_secret_string(secret_arn)
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError(f"Secret {secret_arn} must contain a JSON object.")
    return parsed


def load_google_service_account_info() -> Dict[str, Any]:
    if not config.GOOGLE_SERVICE_ACCOUNT_SECRET_ARN:
        raise ValueError("GOOGLE_SERVICE_ACCOUNT_SECRET_ARN is not configured.")
    return get_secret_json(config.GOOGLE_SERVICE_ACCOUNT_SECRET_ARN)


def load_apple_root_certificates() -> List[bytes]:
    if not config.APPLE_ROOT_CA_SECRET_ARN:
        raise ValueError("APPLE_ROOT_CA_SECRET_ARN is not configured.")

    raw = get_secret_string(config.APPLE_ROOT_CA_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        certs = parsed.get("certificates")
        if isinstance(certs, list):
            return [str(item).encode("utf-8") for item in certs if str(item).strip()]
        bundle = str(parsed.get("pem_bundle") or "").strip()
        if bundle:
            return _split_pem_bundle(bundle)

    if isinstance(parsed, list):
        return [str(item).encode("utf-8") for item in parsed if str(item).strip()]

    text = str(parsed).strip()
    if not text:
        raise ValueError("Apple root CA secret is empty.")
    return _split_pem_bundle(text)


def load_apple_shared_secret() -> str:
    if not config.APPLE_SHARED_SECRET_SECRET_ARN:
        raise ValueError("APPLE_SHARED_SECRET_SECRET_ARN is not configured.")

    raw = get_secret_string(config.APPLE_SHARED_SECRET_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("shared_secret", "password", "APPLE_SHARED_SECRET"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError("Apple shared secret JSON must include shared_secret.")

    value = str(parsed).strip()
    if not value:
        raise ValueError("Apple shared secret is empty.")
    return value


def load_webhook_secret(secret_arn: str) -> str:
    raw = get_secret_string(secret_arn)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("secret", "webhook_secret", "signing_secret", "key"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(f"Webhook secret JSON at {secret_arn} must include a secret field.")

    value = str(parsed).strip()
    if not value:
        raise ValueError(f"Webhook secret at {secret_arn} is empty.")
    return value


def load_social_auth_secret() -> str:
    if not config.SOCIAL_AUTH_SECRET_ARN:
        raise ValueError("SOCIAL_AUTH_SECRET_ARN is not configured.")

    raw = get_secret_string(config.SOCIAL_AUTH_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("secret", "pepper", "social_auth_secret", "key"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            "Social auth secret JSON must include one of: secret, pepper, social_auth_secret, key."
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("Social auth secret is empty.")
    return value


def load_app_auth_secret() -> str:
    if not config.APP_AUTH_SECRET_ARN:
        raise ValueError("APP_AUTH_SECRET_ARN is not configured.")

    raw = get_secret_string(config.APP_AUTH_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("secret", "jwt_secret", "app_auth_secret", "key"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            "App auth secret JSON must include one of: secret, jwt_secret, app_auth_secret, key."
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("App auth secret is empty.")
    return value


def load_postmark_server_token() -> str:
    if config.POSTMARK_SERVER_TOKEN:
        return config.POSTMARK_SERVER_TOKEN
    if not config.POSTMARK_SERVER_TOKEN_SECRET_ARN:
        raise ValueError(
            "POSTMARK_SERVER_TOKEN or POSTMARK_SERVER_TOKEN_SECRET_ARN must be configured."
        )

    raw = get_secret_string(config.POSTMARK_SERVER_TOKEN_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("token", "server_token", "postmark_server_token", "POSTMARK_SERVER_TOKEN"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            "Postmark token secret JSON must include one of: token, server_token, postmark_server_token, POSTMARK_SERVER_TOKEN."
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("Postmark server token is empty.")
    return value


def load_stibee_access_token() -> str:
    if config.STIBEE_ACCESS_TOKEN:
        return config.STIBEE_ACCESS_TOKEN
    if not config.STIBEE_ACCESS_TOKEN_SECRET_ARN:
        raise ValueError(
            "STIBEE_ACCESS_TOKEN or STIBEE_ACCESS_TOKEN_SECRET_ARN must be configured."
        )

    raw = get_secret_string(config.STIBEE_ACCESS_TOKEN_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("token", "access_token", "stibee_access_token", "STIBEE_ACCESS_TOKEN"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            (
                "Stibee access token secret JSON must include one of: token, "
                "access_token, stibee_access_token, STIBEE_ACCESS_TOKEN."
            )
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("Stibee access token is empty.")
    return value


def load_stibee_webhook_shared_secret() -> str:
    if config.STIBEE_WEBHOOK_SHARED_SECRET:
        return config.STIBEE_WEBHOOK_SHARED_SECRET
    if not config.STIBEE_WEBHOOK_SHARED_SECRET_ARN:
        raise ValueError(
            (
                "STIBEE_WEBHOOK_SHARED_SECRET or "
                "STIBEE_WEBHOOK_SHARED_SECRET_ARN must be configured."
            )
        )

    raw = get_secret_string(config.STIBEE_WEBHOOK_SHARED_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in ("secret", "webhook_secret", "shared_secret", "STIBEE_WEBHOOK_SHARED_SECRET"):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            (
                "Stibee webhook secret JSON must include one of: secret, "
                "webhook_secret, shared_secret, STIBEE_WEBHOOK_SHARED_SECRET."
            )
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("Stibee webhook shared secret is empty.")
    return value


def load_posthog_personal_api_key() -> str:
    if config.POSTHOG_PERSONAL_API_KEY:
        return config.POSTHOG_PERSONAL_API_KEY
    if not config.POSTHOG_PERSONAL_API_KEY_SECRET_ARN:
        raise ValueError(
            (
                "POSTHOG_PERSONAL_API_KEY or "
                "POSTHOG_PERSONAL_API_KEY_SECRET_ARN must be configured."
            )
        )

    raw = get_secret_string(config.POSTHOG_PERSONAL_API_KEY_SECRET_ARN)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in (
            "token",
            "api_key",
            "personal_api_key",
            "POSTHOG_PERSONAL_API_KEY",
        ):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            (
                "PostHog personal API key secret JSON must include one of: "
                "token, api_key, personal_api_key, POSTHOG_PERSONAL_API_KEY."
            )
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError("PostHog personal API key is empty.")
    return value


def _split_pem_bundle(bundle: str) -> List[bytes]:
    blocks: List[bytes] = []
    current: List[str] = []
    for line in bundle.splitlines():
        current.append(line)
        if "END CERTIFICATE" in line:
            blocks.append(("\n".join(current).strip() + "\n").encode("utf-8"))
            current = []

    if not blocks and bundle.strip():
        blocks.append((bundle.strip() + "\n").encode("utf-8"))
    return blocks
