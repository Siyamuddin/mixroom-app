from __future__ import annotations

import base64
import binascii
import json
import time
from typing import Any, Dict, List, Tuple

import boto3

from . import config

_secrets_client = boto3.client("secretsmanager")
_ssm_client = boto3.client("ssm")
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


def get_parameter_string(parameter_name: str) -> str:
    name = str(parameter_name or "").strip()
    if not name:
        raise ValueError("Missing SSM parameter name.")

    cache_key = f"ssm:{name}"
    cached = _secret_cache.get(cache_key)
    now = time.time()
    if cached and now - cached[0] < _cache_ttl_seconds():
        return cached[1]

    response = _ssm_client.get_parameter(Name=name, WithDecryption=True)
    parameter = response.get("Parameter") or {}
    value = str(parameter.get("Value") or "")
    _secret_cache[cache_key] = (now, value)
    return value


def get_configured_secret_string(
    *,
    parameter_name: str = "",
    secret_arn: str = "",
    label: str = "secret",
) -> str:
    if str(parameter_name or "").strip():
        return get_parameter_string(parameter_name)
    if str(secret_arn or "").strip():
        return get_secret_string(secret_arn)
    raise ValueError(f"{label} is not configured.")


def put_secure_parameter_string(parameter_name: str, parameter_value: str) -> str:
    name = str(parameter_name or "").strip()
    if not name:
        raise ValueError("Missing SSM parameter name.")
    value = str(parameter_value or "")
    _ssm_client.put_parameter(
        Name=name,
        Value=value,
        Type="SecureString",
        Overwrite=True,
    )
    _secret_cache.pop(f"ssm:{name}", None)
    return name


def get_secret_json(secret_arn: str = "", parameter_name: str = "") -> Dict[str, Any]:
    raw = get_configured_secret_string(
        parameter_name=parameter_name,
        secret_arn=secret_arn,
        label="JSON secret",
    )
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        source = parameter_name or secret_arn
        raise ValueError(f"Secret {source} must contain a JSON object.")
    return parsed


def load_google_service_account_info() -> Dict[str, Any]:
    return get_secret_json(
        secret_arn=config.GOOGLE_SERVICE_ACCOUNT_SECRET_ARN,
        parameter_name=config.GOOGLE_SERVICE_ACCOUNT_PARAMETER_NAME,
    )


def load_apple_root_certificates() -> List[bytes]:
    raw = get_configured_secret_string(
        parameter_name=config.APPLE_ROOT_CA_PARAMETER_NAME,
        secret_arn=config.APPLE_ROOT_CA_SECRET_ARN,
        label="APPLE_ROOT_CA_PARAMETER_NAME or APPLE_ROOT_CA_SECRET_ARN",
    )
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        der_certs = parsed.get("certificates_der_base64")
        if isinstance(der_certs, list):
            return [_certificate_text_to_der(str(item)) for item in der_certs if str(item).strip()]
        certs = parsed.get("certificates")
        if isinstance(certs, list):
            return [_certificate_text_to_der(str(item)) for item in certs if str(item).strip()]
        bundle = str(parsed.get("pem_bundle") or "").strip()
        if bundle:
            return _split_pem_bundle(bundle)

    if isinstance(parsed, list):
        return [_certificate_text_to_der(str(item)) for item in parsed if str(item).strip()]

    text = str(parsed).strip()
    if not text:
        raise ValueError("Apple root CA secret is empty.")
    return _split_pem_bundle(text)


def load_apple_shared_secret() -> str:
    raw = get_configured_secret_string(
        parameter_name=config.APPLE_SHARED_SECRET_PARAMETER_NAME,
        secret_arn=config.APPLE_SHARED_SECRET_SECRET_ARN,
        label="APPLE_SHARED_SECRET_PARAMETER_NAME or APPLE_SHARED_SECRET_SECRET_ARN",
    )
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


def load_webhook_secret(secret_arn: str = "", parameter_name: str = "") -> str:
    raw = get_configured_secret_string(
        parameter_name=parameter_name,
        secret_arn=secret_arn,
        label="webhook secret",
    )
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


def load_provider_api_key(secret_arn: str = "", parameter_name: str = "") -> str:
    raw = get_configured_secret_string(
        parameter_name=parameter_name,
        secret_arn=secret_arn,
        label="provider API key",
    )
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    if isinstance(parsed, dict):
        for key in (
            "api_key",
            "secret_key",
            "token",
            "key",
            "PADDLE_API_KEY",
            "TOSS_SECRET_KEY",
            "billing_key",
            "TOSS_BILLING_KEY",
        ):
            value = str(parsed.get(key) or "").strip()
            if value:
                return value
        raise ValueError(
            f"Provider API key JSON at {parameter_name or secret_arn} must include api_key, secret_key, token, or key."
        )

    value = str(parsed).strip()
    if not value:
        raise ValueError(f"Provider API key at {parameter_name or secret_arn} is empty.")
    return value


def load_social_auth_secret() -> str:
    raw = get_configured_secret_string(
        parameter_name=config.SOCIAL_AUTH_SECRET_PARAMETER_NAME,
        secret_arn=config.SOCIAL_AUTH_SECRET_ARN,
        label="SOCIAL_AUTH_SECRET_PARAMETER_NAME or SOCIAL_AUTH_SECRET_ARN",
    )
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
    raw = get_configured_secret_string(
        parameter_name=config.APP_AUTH_SECRET_PARAMETER_NAME,
        secret_arn=config.APP_AUTH_SECRET_ARN,
        label="APP_AUTH_SECRET_PARAMETER_NAME or APP_AUTH_SECRET_ARN",
    )
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

    raw = get_configured_secret_string(
        parameter_name=config.POSTMARK_SERVER_TOKEN_PARAMETER_NAME,
        secret_arn=config.POSTMARK_SERVER_TOKEN_SECRET_ARN,
        label="POSTMARK_SERVER_TOKEN, POSTMARK_SERVER_TOKEN_PARAMETER_NAME, or POSTMARK_SERVER_TOKEN_SECRET_ARN",
    )
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

    raw = get_configured_secret_string(
        parameter_name=config.STIBEE_ACCESS_TOKEN_PARAMETER_NAME,
        secret_arn=config.STIBEE_ACCESS_TOKEN_SECRET_ARN,
        label="STIBEE_ACCESS_TOKEN, STIBEE_ACCESS_TOKEN_PARAMETER_NAME, or STIBEE_ACCESS_TOKEN_SECRET_ARN",
    )
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


def load_cloud_project_r2_credentials() -> Dict[str, str]:
    raw = get_configured_secret_string(
        parameter_name=config.CLOUD_PROJECT_R2_SECRET_ACCESS_KEY_PARAMETER_NAME,
        secret_arn=config.CLOUD_PROJECT_R2_SECRET_ACCESS_KEY_SECRET_ARN,
        label="CLOUD_PROJECT_R2_SECRET_ACCESS_KEY_PARAMETER_NAME or CLOUD_PROJECT_R2_SECRET_ACCESS_KEY_SECRET_ARN",
    )
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw

    access_key_id = config.CLOUD_PROJECT_R2_ACCESS_KEY_ID
    secret_access_key = ""
    account_id = config.CLOUD_PROJECT_R2_ACCOUNT_ID
    endpoint_url = config.CLOUD_PROJECT_R2_ENDPOINT_URL

    if isinstance(parsed, dict):
        for key in ("secret_access_key", "secretAccessKey", "r2_secret_access_key"):
            value = str(parsed.get(key) or "").strip()
            if value:
                secret_access_key = value
                break
        for key in ("access_key_id", "accessKeyId", "r2_access_key_id"):
            value = str(parsed.get(key) or "").strip()
            if value:
                access_key_id = value
                break
        for key in ("account_id", "accountId", "r2_account_id"):
            value = str(parsed.get(key) or "").strip()
            if value:
                account_id = value
                break
        for key in ("endpoint_url", "endpointUrl", "r2_endpoint_url"):
            value = str(parsed.get(key) or "").strip()
            if value:
                endpoint_url = value
                break
    else:
        secret_access_key = str(parsed).strip()

    if not access_key_id:
        raise ValueError("R2 access key ID is not configured.")
    if not secret_access_key:
        raise ValueError("R2 secret access key is empty.")
    if not endpoint_url:
        if not account_id:
            raise ValueError("R2 account ID or endpoint URL is not configured.")
        endpoint_url = f"https://{account_id}.r2.cloudflarestorage.com"

    return {
        "access_key_id": access_key_id,
        "secret_access_key": secret_access_key,
        "account_id": account_id,
        "endpoint_url": endpoint_url,
    }


def load_stibee_webhook_shared_secret() -> str:
    if config.STIBEE_WEBHOOK_SHARED_SECRET:
        return config.STIBEE_WEBHOOK_SHARED_SECRET

    raw = get_configured_secret_string(
        parameter_name=config.STIBEE_WEBHOOK_SHARED_SECRET_PARAMETER_NAME,
        secret_arn=config.STIBEE_WEBHOOK_SHARED_SECRET_ARN,
        label=(
            "STIBEE_WEBHOOK_SHARED_SECRET, "
            "STIBEE_WEBHOOK_SHARED_SECRET_PARAMETER_NAME, or "
            "STIBEE_WEBHOOK_SHARED_SECRET_ARN"
        ),
    )
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

    raw = get_configured_secret_string(
        parameter_name=config.POSTHOG_PERSONAL_API_KEY_PARAMETER_NAME,
        secret_arn=config.POSTHOG_PERSONAL_API_KEY_SECRET_ARN,
        label=(
            "POSTHOG_PERSONAL_API_KEY, "
            "POSTHOG_PERSONAL_API_KEY_PARAMETER_NAME, or "
            "POSTHOG_PERSONAL_API_KEY_SECRET_ARN"
        ),
    )
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
    blocks: List[str] = []
    current: List[str] = []
    for line in bundle.splitlines():
        current.append(line)
        if "END CERTIFICATE" in line:
            blocks.append("\n".join(current).strip() + "\n")
            current = []

    if not blocks and bundle.strip():
        blocks.append(bundle.strip() + "\n")
    return [_certificate_text_to_der(block) for block in blocks]


def _certificate_text_to_der(value: str) -> bytes:
    text = str(value or "").strip()
    if not text:
        raise ValueError("Apple root certificate entry is empty.")

    if "BEGIN CERTIFICATE" in text:
        lines = [
            line.strip()
            for line in text.splitlines()
            if line.strip()
            and "BEGIN CERTIFICATE" not in line
            and "END CERTIFICATE" not in line
        ]
        text = "".join(lines)

    try:
        return base64.b64decode(text, validate=True)
    except binascii.Error as exc:
        raise ValueError("Apple root certificate must be PEM or base64 DER.") from exc
