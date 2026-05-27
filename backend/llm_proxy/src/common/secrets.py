from __future__ import annotations

import json
import time
from typing import Any

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local test fallback
    boto3 = None


_cache: dict[str, tuple[float, str]] = {}


def _cache_ttl_seconds(default: int = 300) -> int:
    try:
        import os

        return max(
            30,
            int(
                os.environ.get("LLM_SECRET_CACHE_TTL_SECONDS")
                or os.environ.get("OPENAI_SECRET_CACHE_TTL_SECONDS")
                or str(default)
            ),
        )
    except (TypeError, ValueError):
        return max(30, default)


def get_parameter_string(parameter_name: str, *, ttl_seconds: int | None = None) -> str:
    name = str(parameter_name or "").strip()
    if not name:
        raise ValueError("Missing SSM parameter name.")
    if boto3 is None:
        raise RuntimeError("boto3 is required to read SSM parameter values.")

    cache_key = f"ssm:{name}"
    now = time.time()
    cached = _cache.get(cache_key)
    ttl = _cache_ttl_seconds() if ttl_seconds is None else max(30, ttl_seconds)
    if cached and now - cached[0] < ttl:
        return cached[1]

    client = boto3.client("ssm")
    result = client.get_parameter(Name=name, WithDecryption=True)
    parameter = result.get("Parameter") or {}
    value = str(parameter.get("Value") or "")
    _cache[cache_key] = (now, value)
    return value


def get_secret_string(secret_arn: str, *, ttl_seconds: int | None = None) -> str:
    arn = str(secret_arn or "").strip()
    if not arn:
        raise ValueError("Missing secret ARN.")
    if boto3 is None:
        raise RuntimeError("boto3 is required to read Secrets Manager values.")

    cache_key = f"secretsmanager:{arn}"
    now = time.time()
    cached = _cache.get(cache_key)
    ttl = _cache_ttl_seconds() if ttl_seconds is None else max(30, ttl_seconds)
    if cached and now - cached[0] < ttl:
        return cached[1]

    client = boto3.client("secretsmanager")
    result = client.get_secret_value(SecretId=arn)
    value = _secret_response_to_string(result)
    _cache[cache_key] = (now, value)
    return value


def get_configured_secret_string(
    *,
    parameter_name: str = "",
    secret_arn: str = "",
    label: str = "secret",
    ttl_seconds: int | None = None,
) -> str:
    if str(parameter_name or "").strip():
        return get_parameter_string(parameter_name, ttl_seconds=ttl_seconds)
    if str(secret_arn or "").strip():
        return get_secret_string(secret_arn, ttl_seconds=ttl_seconds)
    raise ValueError(f"{label} is not configured.")


def parse_json_or_text(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def _secret_response_to_string(result: dict[str, Any]) -> str:
    secret_string = result.get("SecretString")
    if secret_string:
        return str(secret_string).strip()
    secret_binary = result.get("SecretBinary")
    if isinstance(secret_binary, (bytes, bytearray)):
        import base64

        return base64.b64decode(secret_binary).decode("utf-8").strip()
    return ""
