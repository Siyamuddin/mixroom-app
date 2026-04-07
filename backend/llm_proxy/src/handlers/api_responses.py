from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import time
from typing import Any, Dict
from uuid import uuid4

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

from common.ai_limits import (
    apply_server_output_token_cap,
    calculate_credit_cost,
    calculate_token_cost,
    estimate_reserved_tokens,
    get_feature_base_cost,
    get_prompt_limits,
    get_user_tier,
    validate_feature,
)
from common.ai_runtime_config import get_ai_feature_runtime
from common.analytics import (
    analytics_enabled_from_body,
    build_event_properties,
    capture_event,
    client_context_from_body,
)
from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.llm_contract import (
    DEFAULT_MODEL,
    _supports_temperature,
    build_llm_request_from_mixroom_payload,
    normalize_openai_compatible_request,
)
from common.llm_provider import DEFAULT_PROVIDER, get_provider
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.usage_repository import AiUsageRepository

_secret_cache: Any | None = None
_secret_cache_loaded_at: float | None = None
_usage_repo = AiUsageRepository()
_STRUCTURED_MIXROOM_FIELDS = frozenset(
    {
        "conversation",
        "user_text",
        "project_snapshot",
        "selection_snapshot",
        "pending_mix",
        "request_overrides",
    }
)
_ALLOWED_MIX_INTENT_KINDS = frozenset(
    {
        "gain",
        "pan",
        "eq",
        "reverb",
        "delay",
        "distortion",
        "deesser",
        "compressor",
        "limiter",
        "clipper",
        "balance",
    }
)
_TOOL_TEXT_LEAK_MARKERS = (
    "mix_model_request",
    "daw_assistant_actions",
    "informational_response",
    '"assistant_message"',
    '"row_index"',
    '"target_id"',
)
_INVALID_STRUCTURED_OUTPUT_MESSAGE = (
    "I couldn't complete that request just now. Please try again."
)

init_sentry("mixroom-llm-proxy")


def _env_value(*keys: str, default: str = "") -> str:
    for key in keys:
        value = os.environ.get(key)
        if value is None:
            continue
        normalized = str(value).strip()
        if normalized:
            return normalized
    return default


def _secret_cache_ttl_seconds() -> int:
    raw = _env_value(
        "LLM_SECRET_CACHE_TTL_SECONDS",
        "OPENAI_SECRET_CACHE_TTL_SECONDS",
        default="300",
    )
    try:
        value = int(raw)
    except ValueError:
        return 300
    return max(0, value)


def _provider_secret_key_names(provider_name: str) -> tuple[str, ...]:
    normalized = provider_name.strip().lower()
    if normalized == "claude":
        return ("LLM_API_KEY", "ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "api_key")
    if normalized == "gemini":
        return ("LLM_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY", "api_key")
    return ("LLM_API_KEY", "OPENAI_API_KEY", "api_key")


def _provider_direct_env_names(provider_name: str) -> tuple[str, ...]:
    normalized = provider_name.strip().lower()
    if normalized == "claude":
        return ("LLM_API_KEY", "ANTHROPIC_API_KEY", "CLAUDE_API_KEY")
    if normalized == "gemini":
        return ("LLM_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY")
    return ("LLM_API_KEY", "OPENAI_API_KEY")


def _extract_api_key_from_secret(secret_value: Any, provider_name: str) -> str:
    if isinstance(secret_value, str):
        return secret_value.strip()

    if not isinstance(secret_value, dict):
        return ""

    candidates = [secret_value.get(key) for key in _provider_secret_key_names(provider_name)]
    if not any(candidates):
        candidates.extend(
            value
            for key, value in secret_value.items()
            if key.endswith("_API_KEY") and isinstance(value, str)
        )
    if not any(candidates) and len(secret_value) == 1:
        only_value = next(iter(secret_value.values()))
        if isinstance(only_value, str):
            candidates.append(only_value)

    return next(
        (
            str(candidate).strip()
            for candidate in candidates
            if isinstance(candidate, str) and candidate.strip()
        ),
        "",
    )


def _load_api_key(provider_name: str = DEFAULT_PROVIDER) -> str:
    direct = _env_value(*_provider_direct_env_names(provider_name))
    if direct:
        return direct

    secret_arn = _env_value("LLM_API_KEY_SECRET_ARN", "OPENAI_API_KEY_SECRET_ARN")
    if not secret_arn:
        return ""

    global _secret_cache
    global _secret_cache_loaded_at
    ttl_seconds = _secret_cache_ttl_seconds()
    now = time.time()
    if (
        _secret_cache is not None
        and _secret_cache_loaded_at is not None
        and now - _secret_cache_loaded_at < ttl_seconds
    ):
        return _extract_api_key_from_secret(_secret_cache, provider_name)

    if boto3 is None:
        raise RuntimeError("boto3 is required to read Secrets Manager values.")

    client = boto3.client("secretsmanager")
    result = client.get_secret_value(SecretId=secret_arn)
    secret_string = result.get("SecretString")
    if secret_string:
        try:
            parsed = json.loads(secret_string)
        except json.JSONDecodeError:
            _secret_cache = secret_string.strip()
            _secret_cache_loaded_at = now
            return _extract_api_key_from_secret(_secret_cache, provider_name)

        if isinstance(parsed, (dict, str)):
            _secret_cache = parsed
            _secret_cache_loaded_at = now
            return _extract_api_key_from_secret(_secret_cache, provider_name)

    secret_binary = result.get("SecretBinary")
    if isinstance(secret_binary, (bytes, bytearray)):
        decoded_secret = base64.b64decode(secret_binary).decode("utf-8").strip()
        try:
            _secret_cache = json.loads(decoded_secret)
        except json.JSONDecodeError:
            _secret_cache = decoded_secret
        _secret_cache_loaded_at = now
        return _extract_api_key_from_secret(_secret_cache, provider_name)

    return ""


def _read_event_body(event: Dict[str, Any]) -> str:
    raw_body = event.get("body") or ""
    if not event.get("isBase64Encoded"):
        return raw_body
    decoded = base64.b64decode(raw_body)
    return decoded.decode("utf-8")


def _event_http_method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    method = (
        http.get("method")
        or request_context.get("httpMethod")
        or event.get("httpMethod")
        or "POST"
    )
    return str(method).strip().upper() or "POST"


def _event_path(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    route_key = str(request_context.get("routeKey") or "").strip()
    if route_key:
        parts = route_key.split(" ", 1)
        if len(parts) == 2 and parts[1].strip():
            return parts[1].strip()
    for key in ("rawPath", "path"):
        value = event.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _configured_model() -> str:
    return _env_value("LLM_MODEL", "OPENAI_MODEL")


def _provider_name() -> str:
    return _env_value("LLM_PROVIDER", default=DEFAULT_PROVIDER).lower()


def _request_timeout_seconds() -> int:
    raw = _env_value("LLM_TIMEOUT_SECONDS", "OPENAI_TIMEOUT_SECONDS", default="30")
    try:
        value = int(raw)
    except ValueError:
        return 30
    return max(1, value)


def _normalize_request_body(
    body: Dict[str, Any],
    *,
    default_model: str,
    ai_feature: str,
) -> Dict[str, Any]:
    if any(key in body for key in _STRUCTURED_MIXROOM_FIELDS):
        return build_llm_request_from_mixroom_payload(
            body,
            default_model=default_model,
            ai_feature=ai_feature,
        )
    return normalize_openai_compatible_request(body, default_model=default_model)


def _usage_from_payload(payload: Dict[str, Any]) -> tuple[int, int, int]:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return 0, 0, 0

    prompt_tokens = int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0)
    completion_tokens = int(
        usage.get("output_tokens") or usage.get("completion_tokens") or 0
    )
    total_tokens = int(
        usage.get("total_tokens") or (prompt_tokens + completion_tokens)
    )
    return prompt_tokens, completion_tokens, total_tokens


def _cached_prompt_tokens_from_payload(payload: Dict[str, Any]) -> int:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return 0

    for details_key in ("input_tokens_details", "prompt_tokens_details"):
        details = usage.get(details_key)
        if not isinstance(details, dict):
            continue
        try:
            return int(details.get("cached_tokens") or 0)
        except (TypeError, ValueError):
            return 0
    return 0


def _update_request_log_context_with_cache_request(
    request_log_context: Dict[str, Any],
    request_body: Dict[str, Any],
) -> None:
    request_log_context["model"] = str(request_body.get("model") or "").strip()
    request_log_context["prompt_cache_key"] = str(
        request_body.get("prompt_cache_key") or ""
    ).strip()
    request_log_context["prompt_cache_retention"] = str(
        request_body.get("prompt_cache_retention") or ""
    ).strip()


def _update_request_log_context_with_cache_response(
    request_log_context: Dict[str, Any],
    payload: Dict[str, Any],
) -> None:
    prompt_tokens, _, _ = _usage_from_payload(payload)
    cached_prompt_tokens = _cached_prompt_tokens_from_payload(payload)
    if prompt_tokens > 0:
        request_log_context["prompt_tokens"] = prompt_tokens
    if cached_prompt_tokens > 0:
        request_log_context["cached_prompt_tokens"] = cached_prompt_tokens
        request_log_context["prompt_cache_hit"] = True


def _limit_error_payload(
    limit_reason: str,
    *,
    prompt_rate_limit: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if limit_reason == "weekly_prompts":
        message = "Weekly prompt limit reached"
        error = "prompt_rate_limit_hit"
    elif limit_reason == "daily_prompts":
        message = "Daily prompt limit reached"
        error = "prompt_rate_limit_hit"
    elif limit_reason == "monthly_tokens":
        message = "Monthly AI token limit reached"
        error = "ai_usage_limit_hit"
    else:
        message = "Daily AI limit reached"
        error = "ai_usage_limit_hit"
    return {
        "error": error,
        "message": message,
        "limit_reason": limit_reason,
        "prompt_rate_limit": prompt_rate_limit or {},
        "upgrade_available": False,
    }


def _limit_type(limit_reason: str) -> str:
    if limit_reason == "monthly_tokens":
        return "monthly"
    if limit_reason == "weekly_prompts":
        return "weekly"
    return "daily"


def _error_code_from_payload(payload: Dict[str, Any], status_code: int) -> str:
    error = payload.get("error")
    if isinstance(error, dict):
        for key in ("code", "type", "message"):
            value = error.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    if isinstance(error, str) and error.strip():
        return error.strip()
    return f"status_{status_code}"


def _compact_dict(values: Dict[str, Any]) -> Dict[str, Any]:
    return {
        key: value
        for key, value in values.items()
        if value is not None and (not isinstance(value, str) or value.strip())
    }


def _prompt_trace_id_from_body(body: Dict[str, Any]) -> str:
    raw = str(body.get("prompt_trace_id") or "").strip()
    return raw or str(uuid4())


def _runtime_config_fingerprint(
    *,
    ai_feature: str,
    provider_name: str,
    request_body: Dict[str, Any],
    runtime_config: Dict[str, Any],
) -> str:
    system_prompt = str(
        request_body.get("instructions") or runtime_config.get("system_prompt") or ""
    )
    system_prompt_hash = hashlib.sha256(system_prompt.encode("utf-8")).hexdigest()[:16]
    payload = {
        "feature": ai_feature,
        "provider": provider_name,
        "model": str(request_body.get("model") or "").strip(),
        "temperature": request_body.get("temperature"),
        "max_output_tokens": request_body.get("max_output_tokens"),
        "reasoning": request_body.get("reasoning"),
        "prompt_cache_retention": request_body.get("prompt_cache_retention"),
        "has_system_prompt_override": runtime_config.get("has_system_prompt_override") is True,
        "system_prompt_hash": system_prompt_hash,
    }
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return digest[:16]


def _resolved_tool_name_from_payload(payload: Dict[str, Any]) -> str:
    output = payload.get("output")
    if not isinstance(output, list):
        return ""

    for item in output:
        if not isinstance(item, dict):
            continue
        if str(item.get("type") or "").strip() != "function_call":
            continue
        name = item.get("name")
        if isinstance(name, str) and name.strip():
            return name.strip()
    return ""


def _latest_user_message(request_body: Dict[str, Any]) -> str:
    messages = request_body.get("messages")
    if not isinstance(messages, list):
        return ""
    for message in reversed(messages):
        if not isinstance(message, dict):
            continue
        if str(message.get("role") or "").strip().lower() != "user":
            continue
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
    return ""


def _contains_non_ascii_letters(text: str) -> bool:
    return any(ord(char) > 127 and char.isalpha() for char in text)


def _is_probably_english(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return False
    if _contains_non_ascii_letters(stripped):
        return False
    letters = [char for char in stripped if char.isalpha()]
    if not letters:
        return True
    ascii_letters = [char for char in letters if ord(char) < 128]
    return len(ascii_letters) / len(letters) >= 0.95


def _fallback_assistant_message(tool_name: str) -> str:
    if tool_name == "mix_model_request":
        return "Applied the requested mix changes."
    if tool_name == "daw_assistant_actions":
        return "Here are the relevant steps."
    return _INVALID_STRUCTURED_OUTPUT_MESSAGE


def _sanitize_user_facing_text(
    value: Any,
    *,
    tool_name: str,
    user_text: str,
) -> str:
    raw = str(value or "").strip()
    fallback = _fallback_assistant_message(tool_name)
    if not raw:
        return fallback

    lower = raw.lower()
    if any(marker in lower for marker in _TOOL_TEXT_LEAK_MARKERS):
        return fallback
    if raw.startswith("{") or raw.startswith("["):
        return fallback
    return raw


def _short_tutorial_assistant_message(value: Any, *, user_text: str) -> str:
    raw = _sanitize_user_facing_text(
        value,
        tool_name="daw_assistant_actions",
        user_text=user_text,
    )
    normalized = raw.replace("\n", " ").strip()
    if (
        not normalized
        or normalized == _fallback_assistant_message("daw_assistant_actions")
    ):
        return "Showing you in the UI." if _is_probably_english(user_text) else raw

    looks_verbose = (
        "\n" in raw
        or len(normalized) > 60
        or bool(re.search(r"[.!?].+\S", normalized))
        or normalized.lower().startswith("here's how")
        or normalized.lower().startswith("here is how")
        or normalized.lower().startswith("here's where")
        or normalized.lower().startswith("here is where")
    )
    if looks_verbose and _is_probably_english(user_text):
        return "Showing you in the UI."

    first_sentence = re.split(r"(?<=[.!?])\s+", normalized, maxsplit=1)[0].strip()
    concise = (
        f"{first_sentence[:89].rstrip()}."
        if len(first_sentence) > 90
        else first_sentence
    )
    if concise and len(concise) <= 90:
        return concise
    return "Showing you in the UI." if _is_probably_english(user_text) else raw


def _user_requested_global_clip_scope(user_text: str) -> bool:
    lowered = str(user_text or "").lower()
    return bool(
        re.search(r"\ball clips\b", lowered)
        or re.search(r"\bmove everything\b", lowered)
        or re.search(r"\bdelete everything\b", lowered)
        or re.search(r"\beverything\b", lowered)
        or re.search(r"\bwhole project\b", lowered)
        or re.search(r"\ball tracks\b", lowered)
    )


def _normalize_tutorial_target_id(target_id: Any) -> Any:
    raw = str(target_id or "").strip()
    match = re.fullmatch(r"(row:\d+:)fx_index:([^:]+)(:param:.+)?", raw)
    if not match:
        return target_id
    effect_ref = match.group(2).strip()
    if effect_ref.isdigit():
        return target_id
    suffix = match.group(3) or ""
    return f"{match.group(1)}fx_contains:{effect_ref}{suffix}"


def _normalize_daw_action_payloads(
    actions: list[dict[str, Any]],
    *,
    user_text: str,
) -> list[dict[str, Any]]:
    normalized_actions: list[dict[str, Any]] = []
    for action in actions:
        normalized_action = dict(action)
        data = normalized_action.get("data")
        if not isinstance(data, dict):
            normalized_actions.append(normalized_action)
            continue
        normalized_data = dict(data)
        target = normalized_data.get("target")
        if isinstance(target, dict):
            normalized_target = dict(target)
            normalized_data["target"] = normalized_target
        else:
            normalized_target = None

        action_type = str(normalized_action.get("type") or "").strip().lower()
        if action_type == "tutorial":
            steps = normalized_data.get("steps")
            if isinstance(steps, list):
                repaired_steps = []
                for step in steps:
                    if not isinstance(step, dict):
                        repaired_steps.append(step)
                        continue
                    repaired_step = dict(step)
                    repaired_step["target_id"] = _normalize_tutorial_target_id(
                        repaired_step.get("target_id")
                    )
                    repaired_steps.append(repaired_step)
                normalized_data["steps"] = repaired_steps

        if action_type == "clip_edit" and normalized_target is not None:
            if _user_requested_global_clip_scope(user_text):
                normalized_target["scope"] = "all"
                normalized_target.pop("clip_index", None)
                normalized_target.pop("clip_indices", None)
                normalized_target.pop("row_index", None)
                normalized_target.pop("prefer_selected", None)
                normalized_data["target"] = normalized_target

        normalized_action["data"] = normalized_data
        normalized_actions.append(normalized_action)

    if _user_requested_global_clip_scope(user_text):
        deduped_actions: list[dict[str, Any]] = []
        seen_clip_signatures: set[str] = set()
        for action in normalized_actions:
            if str(action.get("type") or "").strip().lower() != "clip_edit":
                deduped_actions.append(action)
                continue
            data = action.get("data")
            if not isinstance(data, dict):
                deduped_actions.append(action)
                continue
            signature_payload = dict(data)
            signature_target = signature_payload.get("target")
            if isinstance(signature_target, dict):
                signature_target = dict(signature_target)
                signature_payload["target"] = signature_target
            signature = json.dumps(signature_payload, sort_keys=True, default=str)
            if signature in seen_clip_signatures:
                continue
            seen_clip_signatures.add(signature)
            deduped_actions.append(action)
        normalized_actions = deduped_actions

    return normalized_actions


def _decode_tool_arguments(value: Any) -> Dict[str, Any] | None:
    current = value
    for _ in range(4):
        if isinstance(current, dict):
            if set(current.keys()) == {"value"}:
                current = current.get("value")
                continue
            return dict(current)
        if isinstance(current, str):
            stripped = current.strip()
            if not stripped:
                return None
            if stripped.startswith("```") and stripped.endswith("```"):
                stripped = re.sub(
                    r"^```(?:json)?\s*|\s*```$",
                    "",
                    stripped,
                    flags=re.IGNORECASE | re.DOTALL,
                ).strip()
                if not stripped:
                    return None
            try:
                current = json.loads(stripped)
            except json.JSONDecodeError:
                return None
            continue
        return None

    if isinstance(current, dict):
        return dict(current)
    return None


def _user_requested_clipper(user_text: str) -> bool:
    lowered = user_text.lower()
    return bool(
        re.search(r"\bclipper\b", lowered)
        or re.search(r"\bsoft\s+clip\b", lowered)
        or re.search(r"\bhard\s+clip\b", lowered)
    )


def _normalize_mix_model_request_arguments(
    args: Dict[str, Any],
    *,
    user_text: str,
) -> tuple[Dict[str, Any] | None, list[str]]:
    issues: list[str] = []
    normalized = dict(args)
    normalized["assistant_message"] = _sanitize_user_facing_text(
        normalized.get("assistant_message"),
        tool_name="mix_model_request",
        user_text=user_text,
    )

    mode = str(normalized.get("mode") or "").strip().lower()
    if mode not in {"execute", "propose"}:
        issues.append("mix_model_request missing valid mode.")

    actions = normalized.get("actions")
    if not isinstance(actions, list) or not actions:
        issues.append("mix_model_request missing actions array.")
        return None, issues

    wants_clipper = _user_requested_clipper(user_text) and "limiter" not in user_text.lower()
    repaired_actions: list[Dict[str, Any]] = []
    repaired_clipper_intent = False

    for index, action in enumerate(actions):
        if not isinstance(action, dict):
            issues.append(f"mix action {index} is not an object.")
            continue

        goal = action.get("goal")
        if not isinstance(goal, dict):
            issues.append(f"mix action {index} missing goal.")
            continue

        normalized_action = dict(action)
        normalized_goal = dict(goal)
        intents = normalized_goal.get("intents")
        if not isinstance(intents, list) or not intents:
            issues.append(f"mix action {index} missing intents.")
            continue

        repaired_intents: list[Dict[str, Any]] = []
        reset_fx = normalized_goal.get("reset_fx") is True
        for intent in intents:
            if not isinstance(intent, dict):
                issues.append(f"mix action {index} has a non-object intent.")
                continue
            normalized_intent = dict(intent)
            kind = str(normalized_intent.get("kind") or "").strip().lower()
            if wants_clipper and kind == "limiter":
                normalized_intent["kind"] = "clipper"
                kind = "clipper"
                repaired_clipper_intent = True
            if kind not in _ALLOWED_MIX_INTENT_KINDS:
                if reset_fx and kind in {"", "null", "none"}:
                    continue
                issues.append(f"mix action {index} has invalid kind '{kind}'.")
                continue
            repaired_intents.append(normalized_intent)

        if not repaired_intents:
            if reset_fx:
                normalized_goal["intents"] = [
                    {
                        "kind": "balance",
                        "direction": None,
                        "descriptor": None,
                        "confidence": 1.0,
                    }
                ]
            else:
                issues.append(f"mix action {index} has no valid intents.")
                continue
        else:
            normalized_goal["intents"] = repaired_intents

        target = normalized_goal.get("target")
        if not isinstance(target, dict):
            issues.append(f"mix action {index} missing target.")
            continue

        normalized_target = dict(target)
        scope = str(normalized_target.get("scope") or "").strip().lower()
        row_index = normalized_target.get("row_index")
        if scope == "master":
            normalized_target.pop("row_index", None)
            normalized_target.pop("role", None)
        else:
            if isinstance(row_index, (int, float)):
                row_index = int(row_index)
                normalized_target["row_index"] = row_index
            if row_index is not None and (not isinstance(row_index, int) or row_index < 0):
                issues.append(f"mix action {index} emitted invalid row_index.")
                continue

        normalized_goal["target"] = normalized_target
        normalized_action["goal"] = normalized_goal
        repaired_actions.append(normalized_action)

    if not repaired_actions:
        issues.append("mix_model_request had no valid actions.")
        return None, issues

    assistant_message = str(normalized.get("assistant_message") or "").strip().lower()
    if repaired_clipper_intent and "clip" not in assistant_message:
        normalized["assistant_message"] = _fallback_assistant_message("mix_model_request")

    normalized["actions"] = repaired_actions
    return normalized, issues


def _normalize_function_call_arguments(
    tool_name: str,
    raw_arguments: Any,
    *,
    user_text: str,
) -> tuple[Dict[str, Any] | None, list[str]]:
    args = _decode_tool_arguments(raw_arguments)
    if args is None:
        return None, [f"{tool_name} arguments are not a JSON object."]

    if tool_name == "mix_model_request":
        return _normalize_mix_model_request_arguments(args, user_text=user_text)

    if tool_name == "daw_assistant_actions":
        normalized = dict(args)
        actions = normalized.get("actions")
        if not isinstance(actions, list) or not actions:
            return None, ["daw_assistant_actions missing actions array."]
        normalized_actions = [
            dict(action) for action in actions if isinstance(action, dict)
        ]
        normalized["actions"] = _normalize_daw_action_payloads(
            normalized_actions,
            user_text=user_text,
        )
        has_tutorial = any(
            str(action.get("type") or "").strip().lower() == "tutorial"
            for action in normalized["actions"]
        )
        normalized["assistant_message"] = (
            _short_tutorial_assistant_message(
                normalized.get("assistant_message"),
                user_text=user_text,
            )
            if has_tutorial
            else _sanitize_user_facing_text(
                normalized.get("assistant_message"),
                tool_name=tool_name,
                user_text=user_text,
            )
        )
        return normalized, []

    if tool_name == "informational_response":
        normalized = dict(args)
        normalized["message"] = _sanitize_user_facing_text(
            normalized.get("message"),
            tool_name=tool_name,
            user_text=user_text,
        )
        normalized["cancels_pending"] = normalized.get("cancels_pending") is True
        return normalized, []

    return args, []


def _fallback_success_payload(
    *,
    payload: Dict[str, Any],
    message: str,
    soft_error_code: str = "",
) -> Dict[str, Any]:
    body = {
        "id": payload.get("id"),
        "model": payload.get("model"),
        "output": [
            {
                "type": "function_call",
                "name": "informational_response",
                "arguments": {
                    "message": message,
                    "cancels_pending": False,
                },
            }
        ],
        "usage": payload.get("usage") if isinstance(payload.get("usage"), dict) else {},
    }
    if soft_error_code.strip():
        body["soft_error"] = {
            "code": soft_error_code.strip(),
            "usage_refunded": True,
        }
    return body


def _informational_success_payload(
    *,
    payload: Dict[str, Any],
    message: str,
) -> Dict[str, Any]:
    return {
        "id": payload.get("id"),
        "model": payload.get("model"),
        "output": [
            {
                "type": "function_call",
                "name": "informational_response",
                "arguments": {
                    "message": message,
                    "cancels_pending": False,
                },
            }
        ],
        "usage": payload.get("usage") if isinstance(payload.get("usage"), dict) else {},
    }


def _issue_is_refundable(issue: str) -> bool:
    normalized = str(issue or "").strip().lower()
    if not normalized:
        return False
    return normalized in {
        "success payload missing output array.",
        "success payload contained a non-object output item.",
        "message output missing content list.",
        "message output was blank or looked like leaked json.",
        "success payload had no function call or usable assistant text.",
        "function call missing name.",
    } or normalized.endswith("arguments are not a json object.")


def _normalize_success_payload(
    *,
    request_body: Dict[str, Any],
    payload: Dict[str, Any],
) -> tuple[Dict[str, Any], list[str], bool]:
    user_text = _latest_user_message(request_body)
    outputs = payload.get("output")
    if not isinstance(outputs, list):
        issues = ["Success payload missing output array."]
        return _fallback_success_payload(
            payload=payload,
            message=_INVALID_STRUCTURED_OUTPUT_MESSAGE,
            soft_error_code="invalid_structured_output",
        ), issues, True

    normalized_output: list[Dict[str, Any]] = []
    issues: list[str] = []
    saw_function_call = False
    clean_message_texts: list[str] = []

    for item in outputs:
        if not isinstance(item, dict):
            issues.append("Success payload contained a non-object output item.")
            continue

        item_type = str(item.get("type") or "").strip()
        if item_type == "message":
            content = item.get("content")
            if not isinstance(content, list):
                issues.append("Message output missing content list.")
                continue
            for entry in content:
                if not isinstance(entry, dict):
                    continue
                if str(entry.get("type") or "").strip() != "output_text":
                    continue
                text = _sanitize_user_facing_text(
                    entry.get("text"),
                    tool_name="informational_response",
                    user_text=user_text,
                )
                if text == _INVALID_STRUCTURED_OUTPUT_MESSAGE:
                    issues.append("Message output was blank or looked like leaked JSON.")
                else:
                    clean_message_texts.append(text)
            continue

        if item_type != "function_call":
            issues.append(f"Unsupported output type '{item_type}'.")
            continue

        tool_name = str(item.get("name") or "").strip()
        if not tool_name:
            issues.append("Function call missing name.")
            continue

        normalized_args, item_issues = _normalize_function_call_arguments(
            tool_name,
            item.get("arguments"),
            user_text=user_text,
        )
        if normalized_args is None:
            issues.extend(item_issues)
            continue

        issues.extend(item_issues)
        saw_function_call = True
        normalized_item = dict(item)
        normalized_item["arguments"] = normalized_args
        normalized_output.append(normalized_item)

    if saw_function_call:
        if issues:
            return _fallback_success_payload(
                payload=payload,
                message=_INVALID_STRUCTURED_OUTPUT_MESSAGE,
                soft_error_code=(
                    "invalid_structured_output"
                    if any(_issue_is_refundable(issue) for issue in issues)
                    else ""
                ),
            ), issues, any(_issue_is_refundable(issue) for issue in issues)
        normalized_payload = dict(payload)
        normalized_payload["output"] = normalized_output
        return normalized_payload, [], False

    if clean_message_texts and not issues:
        return _informational_success_payload(
            payload=payload,
            message=clean_message_texts[0],
        ), [], False

    if not clean_message_texts and not issues:
        issues.append("Success payload had no function call or usable assistant text.")

    if issues:
        return _fallback_success_payload(
            payload=payload,
            message=_INVALID_STRUCTURED_OUTPUT_MESSAGE,
            soft_error_code=(
                "invalid_structured_output"
                if any(_issue_is_refundable(issue) for issue in issues)
                else ""
            ),
        ), issues, any(_issue_is_refundable(issue) for issue in issues)
    return _informational_success_payload(
        payload=payload,
        message=_INVALID_STRUCTURED_OUTPUT_MESSAGE,
    ), [], False


def _safe_log_usage_event(**kwargs: Any) -> None:
    try:
        _usage_repo.log_usage_event(**kwargs)
    except Exception as error:
        capture_exception(
            error,
            context={"service": "llm_proxy", "event_type": "ai_usage_event"},
            tags={"service": "llm_proxy"},
        )


def _get_prompt_rate_limit_status(
    *,
    user_id: str,
    subscription_tier: str,
    prompt_limits: dict[str, int],
) -> dict[str, Any]:
    return _usage_repo.get_prompt_limit_status(
        user_id,
        subscription_tier=subscription_tier,
        daily_prompt_limit=int(prompt_limits.get("daily_prompts") or 0),
        weekly_prompt_limit=int(prompt_limits.get("weekly_prompts") or 0),
    )


def _apply_ai_runtime_overrides(
    request_body: Dict[str, Any],
    *,
    ai_feature: str,
    runtime_config: Dict[str, Any],
    is_structured_request: bool,
) -> None:
    resolved_model = str(request_body.get("model") or runtime_config.get("model") or "").strip()
    if runtime_config.get("has_model_override"):
        resolved_model = str(runtime_config.get("model") or resolved_model).strip()
    if runtime_config.get("has_model_override") and resolved_model:
        request_body["model"] = resolved_model

    if is_structured_request and runtime_config.get("has_system_prompt_override"):
        system_prompt = str(runtime_config.get("system_prompt") or "").strip()
        if system_prompt:
            request_body["instructions"] = system_prompt

    prompt_cache_retention = str(runtime_config.get("prompt_cache_retention") or "").strip()
    if runtime_config.get("has_prompt_cache_retention_override") and prompt_cache_retention:
        request_body["prompt_cache_retention"] = prompt_cache_retention

    max_output_tokens = runtime_config.get("max_output_tokens")
    if (
        runtime_config.get("has_max_output_tokens_override")
        and isinstance(max_output_tokens, int)
        and max_output_tokens > 0
    ):
        request_body["max_output_tokens"] = max_output_tokens

    if _supports_temperature(resolved_model):
        temperature = runtime_config.get("temperature")
        if runtime_config.get("has_temperature_override") and isinstance(temperature, (int, float)):
            request_body["temperature"] = max(0.0, min(float(temperature), 2.0))
        elif "temperature" not in request_body and str(ai_feature).strip() == "video_editor_chat":
            request_body["temperature"] = 0.1
    else:
        request_body.pop("temperature", None)

    reasoning = runtime_config.get("reasoning")
    if runtime_config.get("has_reasoning_override") and isinstance(reasoning, dict) and reasoning:
        request_body["reasoning"] = reasoning


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    user_id = extract_user_id_from_event(event)
    http_method = _event_http_method(event)
    request_path = _event_path(event)
    project_id = ""
    request_log_context = build_request_log_context(
        event,
        _context,
        user_id=user_id,
    )

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_log_context,
            error=error,
        )
        return response

    if not user_id:
        return _finalize(unauthorized(), error="unauthorized")

    user_context = _usage_repo.load_user_context(user_id)
    subscription_tier = get_user_tier(user_context)
    prompt_limits = get_prompt_limits(subscription_tier)

    if http_method == "GET" and request_path.endswith("/v1/llm/limits"):
        try:
            prompt_rate_limit = _get_prompt_rate_limit_status(
                user_id=user_id,
                subscription_tier=subscription_tier,
                prompt_limits=prompt_limits,
            )
        except Exception as error:
            capture_exception(
                error,
                context=request_log_context,
                tags={"service": "llm_proxy"},
            )
            return _finalize(
                json_response(500, {"error": "AI usage limits are unavailable."}),
                error="ai_limits_unavailable",
            )
        return _finalize(json_response(200, {"prompt_rate_limit": prompt_rate_limit}))

    try:
        raw_body = _read_event_body(event)
    except Exception:
        return _finalize(
            json_response(400, {"error": "Request body could not be decoded."}),
            error="body_decode_failed",
        )

    max_request_bytes = int(os.environ.get("MAX_REQUEST_BYTES", "200000"))
    if len(raw_body.encode("utf-8")) > max_request_bytes:
        return _finalize(
            json_response(413, {"error": "Request too large."}),
            error="request_too_large",
        )

    try:
        body = json.loads(raw_body or "{}")
    except json.JSONDecodeError:
        return _finalize(
            json_response(400, {"error": "Invalid JSON body."}),
            error="invalid_json",
        )

    if not isinstance(body, dict):
        return _finalize(
            json_response(400, {"error": "Request body must be an object."}),
            error="invalid_body_type",
        )

    prompt_trace_id = _prompt_trace_id_from_body(body)
    request_log_context["prompt_trace_id"] = prompt_trace_id
    project_id = str(body.get("project_id") or "").strip()
    request_log_context["project_id"] = project_id
    analytics_enabled = analytics_enabled_from_body(body)
    client_context = client_context_from_body(body)
    raw_ai_feature = str(body.get("ai_feature") or "ai_chat").strip() or "ai_chat"
    try:
        ai_feature = validate_feature(raw_ai_feature)
    except ValueError as error:
        return _finalize(
            json_response(400, {"error": str(error)}),
            error="unsupported_ai_feature",
        )

    try:
        provider = get_provider(_provider_name())
    except ValueError as error:
        capture_exception(
            error,
            context=request_log_context,
            tags={"service": "llm_proxy"},
        )
        return _finalize(
            json_response(500, {"error": str(error)}),
            error="invalid_provider",
        )

    configured_model = _configured_model()
    default_model = configured_model or DEFAULT_MODEL
    runtime_config = get_ai_feature_runtime(ai_feature, fallback_model=default_model)
    is_structured_request = any(key in body for key in _STRUCTURED_MIXROOM_FIELDS)

    try:
        request_body = _normalize_request_body(
            body,
            default_model=str(runtime_config.get("model") or default_model),
            ai_feature=ai_feature,
        )
    except ValueError as error:
        return _finalize(
            json_response(400, {"error": str(error)}),
            error="request_normalization_failed",
        )

    allow_model_override = (
        os.environ.get("ALLOW_CLIENT_MODEL_OVERRIDE", "false").lower() == "true"
    )
    if configured_model and (
        not allow_model_override or not request_body.get("model")
    ):
        request_body["model"] = configured_model

    _apply_ai_runtime_overrides(
        request_body,
        ai_feature=ai_feature,
        runtime_config=runtime_config,
        is_structured_request=is_structured_request,
    )

    apply_server_output_token_cap(request_body)
    _update_request_log_context_with_cache_request(request_log_context, request_body)
    runtime_config_fingerprint = _runtime_config_fingerprint(
        ai_feature=ai_feature,
        provider_name=provider.name,
        request_body=request_body,
        runtime_config=runtime_config,
    )
    request_log_context["provider"] = provider.name
    request_log_context["effective_model"] = str(request_body.get("model") or "").strip()
    request_log_context["runtime_config_fingerprint"] = runtime_config_fingerprint

    provider_roundtrip_ms = 0
    openai_api_ms = 0
    response_normalize_ms = 0
    provider_response_id = ""

    def _observability_payload() -> dict[str, Any]:
        return _compact_dict(
            {
                "prompt_trace_id": prompt_trace_id,
                "request_id": request_log_context.get("request_id"),
                "provider": provider.name,
                "effective_model": str(request_body.get("model") or "").strip(),
                "provider_response_id": provider_response_id,
                "runtime_config_fingerprint": runtime_config_fingerprint,
                "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                is True,
                "provider_roundtrip_ms": provider_roundtrip_ms or None,
                "openai_api_ms": openai_api_ms or None,
                "response_normalize_ms": response_normalize_ms or None,
                "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
            }
        )

    api_key = _load_api_key(provider.name)
    if not api_key:
        runtime_error = RuntimeError("LLM API key is not configured.")
        capture_exception(
            runtime_error,
            context=request_log_context,
            tags={"service": "llm_proxy"},
        )
        return _finalize(
            json_response(500, {"error": "LLM API key is not configured."}),
            error="missing_api_key",
        )

    reserved_tokens = estimate_reserved_tokens(request_body)
    reserved_credits = get_feature_base_cost(ai_feature) + calculate_token_cost(
        reserved_tokens
    )

    try:
        reservation = _usage_repo.reserve_usage(
            user_id,
            subscription_tier=subscription_tier,
            reserved_credits=reserved_credits,
            reserved_tokens=reserved_tokens,
            reserved_prompts=1,
            daily_credit_limit=0,
            monthly_token_limit=0,
            daily_prompt_limit=int(prompt_limits.get("daily_prompts") or 0),
            weekly_prompt_limit=int(prompt_limits.get("weekly_prompts") or 0),
        )
    except Exception as error:
        print(
            json.dumps(
                {
                    "message": "AI usage reservation failed",
                    "user_id": user_id,
                    "project_id": project_id,
                    "feature": ai_feature,
                    "subscription_tier": subscription_tier,
                    "reserved_credits": reserved_credits,
                    "reserved_tokens": reserved_tokens,
                    "reserved_prompts": 1,
                    "daily_credit_limit": 0,
                    "monthly_token_limit": 0,
                    "daily_prompt_limit": int(prompt_limits.get("daily_prompts") or 0),
                    "weekly_prompt_limit": int(prompt_limits.get("weekly_prompts") or 0),
                    "error_type": type(error).__name__,
                    "error": str(error),
                }
            )
        )
        capture_exception(
            error,
            context={**request_log_context, "feature": ai_feature},
            tags={"service": "llm_proxy"},
        )
        return _finalize(
            json_response(500, {"error": "AI usage limits are unavailable."}),
            error="ai_limits_unavailable",
        )

    if not reservation.allowed:
        prompt_rate_limit = _get_prompt_rate_limit_status(
            user_id=user_id,
            subscription_tier=subscription_tier,
            prompt_limits=prompt_limits,
        )
        _safe_log_usage_event(
            user_id=user_id,
            project_id=project_id,
            prompt_trace_id=prompt_trace_id,
            request_id=str(request_log_context.get("request_id") or ""),
            feature=ai_feature,
            model=str(request_body.get("model") or ""),
            provider=provider.name,
            prompt_tokens=0,
            completion_tokens=0,
            total_tokens=0,
            credits_charged=0,
            status="rate_limited",
            error_code=reservation.limit_reason or "ai_usage_limit_hit",
            runtime_config_fingerprint=runtime_config_fingerprint,
            app_version=str(client_context.get("app_version") or ""),
            platform=str(client_context.get("platform") or ""),
            proxy_handler_ms_total=int((time.perf_counter() - started_at) * 1000),
        )
        capture_event(
            "ai_usage_limit_hit",
            distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
            properties=build_event_properties(
                user_id=user_id,
                client_context=client_context,
                extra={
                    "project_id": project_id,
                    "ai_feature": ai_feature,
                    "model_name": request_body.get("model"),
                    "prompt_trace_id": prompt_trace_id,
                    "runtime_config_fingerprint": runtime_config_fingerprint,
                    "provider": provider.name,
                    "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
                    "limit_type": _limit_type(reservation.limit_reason or "daily_credits"),
                    "limit_reason": reservation.limit_reason or "daily_credits",
                    "success": False,
                },
            ),
            enabled=analytics_enabled,
        )
        return _finalize(
            json_response(
                429,
                {
                    **_limit_error_payload(
                    reservation.limit_reason,
                    prompt_rate_limit=prompt_rate_limit,
                    ),
                    "observability": _observability_payload(),
                },
            ),
            error="ai_usage_limit_hit",
        )

    print(
        json.dumps(
            {
                "message": "Forwarding LLM request",
                "user_id": user_id,
                "body_bytes": len(raw_body.encode("utf-8")),
                "provider": provider.name,
                "model": request_body.get("model"),
                "tier": subscription_tier,
                "feature": ai_feature,
            }
        )
    )

    capture_event(
        "ai_prompt_submitted",
        distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
        properties=build_event_properties(
            user_id=user_id,
            client_context=client_context,
            extra={
                "project_id": project_id,
                "ai_feature": ai_feature,
                "model_name": request_body.get("model"),
                "prompt_trace_id": prompt_trace_id,
                "runtime_config_fingerprint": runtime_config_fingerprint,
                "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                is True,
                "provider": provider.name,
            },
        ),
        enabled=analytics_enabled,
    )

    try:
        proxy_response = provider.forward_request(
            api_key=api_key,
            request_body=request_body,
            timeout_seconds=_request_timeout_seconds(),
        )
        provider_observability = proxy_response.get("observability") or {}
        if isinstance(provider_observability, dict):
            provider_roundtrip_ms = int(provider_observability.get("provider_roundtrip_ms") or 0)
            openai_api_ms = int(provider_observability.get("openai_api_ms") or 0)
            if provider_roundtrip_ms > 0:
                request_log_context["provider_roundtrip_ms"] = provider_roundtrip_ms
            if openai_api_ms > 0:
                request_log_context["openai_api_ms"] = openai_api_ms
    except Exception as error:
        capture_exception(
            error,
            context={
                **request_log_context,
                "provider": provider.name,
                "model": str(request_body.get("model") or ""),
            },
            tags={"service": "llm_proxy"},
        )
        try:
            _usage_repo.release_usage(
                user_id,
                subscription_tier=subscription_tier,
                reserved_credits=reserved_credits,
                reserved_tokens=reserved_tokens,
                reserved_prompts=1,
                reserved_quota_prompts=reservation.reserved_quota_prompts,
                reserved_grant_prompts=reservation.reserved_grant_prompts,
            )
        except Exception as release_error:
            capture_exception(
                release_error,
                context={**request_log_context, "feature": ai_feature},
                tags={"service": "llm_proxy"},
            )
        _safe_log_usage_event(
            user_id=user_id,
            project_id=project_id,
            prompt_trace_id=prompt_trace_id,
            request_id=str(request_log_context.get("request_id") or ""),
            feature=ai_feature,
            model=str(request_body.get("model") or ""),
            provider=provider.name,
            prompt_tokens=0,
            completion_tokens=0,
            total_tokens=0,
            credits_charged=0,
            status="failed",
            error_code="upstream_unavailable",
            runtime_config_fingerprint=runtime_config_fingerprint,
            app_version=str(client_context.get("app_version") or ""),
            platform=str(client_context.get("platform") or ""),
            proxy_handler_ms_total=int((time.perf_counter() - started_at) * 1000),
            provider_roundtrip_ms=provider_roundtrip_ms,
        )
        capture_event(
            "ai_response_failed",
            distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
            properties=build_event_properties(
                user_id=user_id,
                client_context=client_context,
                extra={
                    "project_id": project_id,
                    "ai_feature": ai_feature,
                    "model_name": request_body.get("model"),
                    "prompt_trace_id": prompt_trace_id,
                    "runtime_config_fingerprint": runtime_config_fingerprint,
                    "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                    is True,
                    "provider": provider.name,
                    "provider_roundtrip_ms": provider_roundtrip_ms or None,
                    "openai_api_ms": openai_api_ms or None,
                    "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
                    "error_code": "upstream_unavailable",
                    "success": False,
                },
            ),
            enabled=analytics_enabled,
        )
        return _finalize(
            json_response(
                502,
                {
                    "error": "LLM upstream unavailable.",
                    "observability": _observability_payload(),
                },
            ),
            error="llm_upstream_unavailable",
        )

    status_code = int(proxy_response.get("statusCode") or 500)
    response_body = proxy_response.get("body")
    response_payload: Dict[str, Any] = {}
    if isinstance(response_body, str):
        try:
            decoded = json.loads(response_body)
            if isinstance(decoded, dict):
                response_payload = decoded
        except json.JSONDecodeError:
            response_payload = {}

    if 200 <= status_code < 300:
        normalization_started_at = time.perf_counter()
        response_payload, normalization_issues, normalization_refunded = _normalize_success_payload(
            request_body=request_body,
            payload=response_payload,
        )
        response_normalize_ms = int((time.perf_counter() - normalization_started_at) * 1000)
        if response_normalize_ms > 0:
            request_log_context["response_normalize_ms"] = response_normalize_ms
        _update_request_log_context_with_cache_response(
            request_log_context,
            response_payload,
        )
        proxy_response = {
            **proxy_response,
            "body": json.dumps(response_payload),
        }
        if normalization_issues:
            print(
                json.dumps(
                    {
                        "message": "Normalized invalid structured LLM output",
                        "provider": provider.name,
                        "model": str(request_body.get("model") or ""),
                        "issues": normalization_issues,
                    }
                )
            )
        prompt_tokens, completion_tokens, total_tokens = _usage_from_payload(response_payload)
        resolved_tool = _resolved_tool_name_from_payload(response_payload)
        if resolved_tool:
            request_log_context["resolved_tool"] = resolved_tool
        provider_response_id = str(response_payload.get("id") or "").strip()
        if provider_response_id:
            request_log_context["provider_response_id"] = provider_response_id
        credits_charged = calculate_credit_cost(
            feature=ai_feature,
            promptTokens=prompt_tokens,
            completionTokens=completion_tokens,
        )
        soft_error = response_payload.get("soft_error")
        refunded_due_to_soft_error = normalization_refunded and isinstance(soft_error, dict) and (
            soft_error.get("usage_refunded") is True
        )
        if refunded_due_to_soft_error:
            try:
                _usage_repo.release_usage(
                    user_id,
                    subscription_tier=subscription_tier,
                    reserved_credits=reserved_credits,
                    reserved_tokens=reserved_tokens,
                    reserved_prompts=1,
                    reserved_quota_prompts=reservation.reserved_quota_prompts,
                    reserved_grant_prompts=reservation.reserved_grant_prompts,
                )
            except Exception as error:
                capture_exception(
                    error,
                    context={**request_log_context, "feature": ai_feature},
                    tags={"service": "llm_proxy"},
                )
        else:
            try:
                _usage_repo.finalize_usage(
                    user_id,
                    subscription_tier=subscription_tier,
                    reserved_credits=reserved_credits,
                    reserved_tokens=reserved_tokens,
                    reserved_prompts=1,
                    reserved_quota_prompts=reservation.reserved_quota_prompts,
                    reserved_grant_prompts=reservation.reserved_grant_prompts,
                    actual_credits=credits_charged,
                    actual_tokens=total_tokens,
                    actual_prompts=1,
                )
            except Exception as error:
                capture_exception(
                    error,
                    context={
                        **request_log_context,
                        "feature": ai_feature,
                        "reserved_prompts": 1,
                        "reserved_credits": reserved_credits,
                        "final_credits": credits_charged,
                        "reserved_tokens": reserved_tokens,
                        "final_tokens": total_tokens,
                    },
                    tags={"service": "llm_proxy"},
                )
        try:
            response_payload["prompt_rate_limit"] = _get_prompt_rate_limit_status(
                user_id=user_id,
                subscription_tier=subscription_tier,
                prompt_limits=prompt_limits,
            )
            proxy_response = {
                **proxy_response,
                "body": json.dumps(response_payload),
            }
        except Exception as error:
            capture_exception(
                error,
                context={**request_log_context, "feature": ai_feature},
                tags={"service": "llm_proxy"},
            )
        _safe_log_usage_event(
            user_id=user_id,
            project_id=project_id,
            prompt_trace_id=prompt_trace_id,
            request_id=str(request_log_context.get("request_id") or ""),
            feature=ai_feature,
            model=str(response_payload.get("model") or request_body.get("model") or ""),
            provider=provider.name,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            credits_charged=0 if refunded_due_to_soft_error else credits_charged,
            status="soft_failed" if refunded_due_to_soft_error else "success",
            resolved_tool=resolved_tool,
            provider_response_id=provider_response_id,
            runtime_config_fingerprint=runtime_config_fingerprint,
            app_version=str(client_context.get("app_version") or ""),
            platform=str(client_context.get("platform") or ""),
            proxy_handler_ms_total=int((time.perf_counter() - started_at) * 1000),
            provider_roundtrip_ms=provider_roundtrip_ms,
            response_normalize_ms=response_normalize_ms,
            error_code=(
                str(soft_error.get("code") or "invalid_structured_output")
                if refunded_due_to_soft_error
                else ""
            ),
        )
        capture_event(
            "ai_response_completed",
            distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
            properties=build_event_properties(
                user_id=user_id,
                client_context=client_context,
                extra={
                    "project_id": project_id,
                    "ai_feature": ai_feature,
                    "model_name": response_payload.get("model") or request_body.get("model"),
                    "prompt_trace_id": prompt_trace_id,
                    "tokens_prompt": prompt_tokens,
                    "tokens_completion": completion_tokens,
                    "tokens_total": total_tokens,
                    "credits_charged": 0 if refunded_due_to_soft_error else credits_charged,
                    "resolved_tool": resolved_tool,
                    "provider_response_id": provider_response_id,
                    "runtime_config_fingerprint": runtime_config_fingerprint,
                    "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                    is True,
                    "provider": provider.name,
                    "provider_roundtrip_ms": provider_roundtrip_ms or None,
                    "openai_api_ms": openai_api_ms or None,
                    "response_normalize_ms": response_normalize_ms or None,
                    "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
                    "success": not refunded_due_to_soft_error,
                    "soft_error_code": (
                        str(soft_error.get("code") or "invalid_structured_output")
                        if refunded_due_to_soft_error
                        else ""
                    ),
                },
            ),
            enabled=analytics_enabled,
        )
        if refunded_due_to_soft_error:
            soft_error_code = (
                str(soft_error.get("code") or "invalid_structured_output").strip()
                or "invalid_structured_output"
            )
            user_text = _latest_user_message(request_body)
            capture_event(
                "ai_response_soft_failed",
                distinct_id=str(client_context.get("distinct_id") or user_id).strip()
                or user_id,
                properties=build_event_properties(
                    user_id=user_id,
                    client_context=client_context,
                    extra={
                        "project_id": project_id,
                        "ai_feature": ai_feature,
                        "model_name": response_payload.get("model")
                        or request_body.get("model"),
                        "prompt_trace_id": prompt_trace_id,
                        "provider_response_id": provider_response_id,
                        "runtime_config_fingerprint": runtime_config_fingerprint,
                        "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                        is True,
                        "provider": provider.name,
                        "provider_roundtrip_ms": provider_roundtrip_ms or None,
                        "openai_api_ms": openai_api_ms or None,
                        "response_normalize_ms": response_normalize_ms or None,
                        "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
                        "soft_error_code": soft_error_code,
                        "refunded_prompt_usage": True,
                        "normalization_issues": normalization_issues,
                        "prompt_length_chars": len(str(user_text or "")),
                        "success": False,
                    },
                ),
                enabled=analytics_enabled,
            )
            capture_exception(
                RuntimeError(f"Refunded soft-failed AI response: {soft_error_code}"),
                context={
                    **request_log_context,
                    "project_id": project_id,
                    "feature": ai_feature,
                    "model": str(
                        response_payload.get("model") or request_body.get("model") or ""
                    ),
                    "provider_response_id": provider_response_id,
                    "soft_error_code": soft_error_code,
                    "refunded_prompt_usage": True,
                    "normalization_issues": normalization_issues,
                    "prompt_length_chars": len(str(user_text or "")),
                },
                tags={
                    "service": "llm_proxy",
                    "error_type": "soft_failed_refunded",
                    "ai_feature": ai_feature,
                },
            )
        response_payload["observability"] = _observability_payload()
        proxy_response = {
            **proxy_response,
            "body": json.dumps(response_payload),
        }
        return _finalize(proxy_response)

    prompt_tokens, completion_tokens, total_tokens = _usage_from_payload(response_payload)
    _update_request_log_context_with_cache_response(
        request_log_context,
        response_payload,
    )
    provider_response_id = str(response_payload.get("id") or "").strip()
    if provider_response_id:
        request_log_context["provider_response_id"] = provider_response_id
    error_code = _error_code_from_payload(response_payload, status_code)
    if status_code >= 400:
        print(
            json.dumps(
                {
                    "message": "LLM upstream non-200 response",
                    "provider": provider.name,
                    "model": str(request_body.get("model") or ""),
                    "status_code": status_code,
                    "error_code": error_code,
                    "response_body": (response_body if isinstance(response_body, str) else "")[
                        :2000
                    ],
                }
            )
        )
    try:
        _usage_repo.release_usage(
            user_id,
            subscription_tier=subscription_tier,
            reserved_credits=reserved_credits,
            reserved_tokens=reserved_tokens,
            reserved_prompts=1,
            reserved_quota_prompts=reservation.reserved_quota_prompts,
            reserved_grant_prompts=reservation.reserved_grant_prompts,
        )
    except Exception as error:
        capture_exception(
            error,
            context={**request_log_context, "feature": ai_feature},
            tags={"service": "llm_proxy"},
        )
    _safe_log_usage_event(
        user_id=user_id,
        project_id=project_id,
        prompt_trace_id=prompt_trace_id,
        request_id=str(request_log_context.get("request_id") or ""),
        feature=ai_feature,
        model=str(request_body.get("model") or ""),
        provider=provider.name,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        credits_charged=0,
        status="failed",
        error_code=error_code,
        provider_response_id=provider_response_id,
        runtime_config_fingerprint=runtime_config_fingerprint,
        app_version=str(client_context.get("app_version") or ""),
        platform=str(client_context.get("platform") or ""),
        proxy_handler_ms_total=int((time.perf_counter() - started_at) * 1000),
        provider_roundtrip_ms=provider_roundtrip_ms,
    )
    capture_event(
        "ai_response_failed",
        distinct_id=str(client_context.get("distinct_id") or user_id).strip() or user_id,
        properties=build_event_properties(
            user_id=user_id,
            client_context=client_context,
            extra={
                "project_id": project_id,
                "ai_feature": ai_feature,
                "model_name": request_body.get("model"),
                "prompt_trace_id": prompt_trace_id,
                "runtime_config_fingerprint": runtime_config_fingerprint,
                "has_system_prompt_override": runtime_config.get("has_system_prompt_override")
                is True,
                "provider": provider.name,
                "provider_response_id": provider_response_id,
                "provider_roundtrip_ms": provider_roundtrip_ms or None,
                "openai_api_ms": openai_api_ms or None,
                "proxy_handler_ms_total": int((time.perf_counter() - started_at) * 1000),
                "error_code": error_code,
                "success": False,
            },
        ),
        enabled=analytics_enabled,
    )
    if status_code >= 500:
        capture_exception(
            RuntimeError(f"LLM upstream returned status {status_code}"),
            context={
                **request_log_context,
                "provider": provider.name,
                "model": str(request_body.get("model") or ""),
            },
            tags={"service": "llm_proxy"},
        )
    response_payload["observability"] = _observability_payload()
    proxy_response = {
        **proxy_response,
        "body": json.dumps(response_payload),
    }
    return _finalize(proxy_response, error=error_code)
