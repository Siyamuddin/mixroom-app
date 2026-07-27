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
from common.llm_provider import (
    DEFAULT_PROVIDER,
    append_openai_conversation_items,
    create_openai_conversation,
    get_provider,
)
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.usage_repository import AiUsageRepository

_secret_cache: Any | None = None
_secret_cache_loaded_at: float | None = None
_usage_repo = AiUsageRepository()
_conversation_state_table: Any | None = None
_STRUCTURED_MIXROOM_FIELDS = frozenset(
    {
        "conversation",
        "user_text",
        "project_snapshot",
        "selection_snapshot",
        "library_snapshot",
        "pending_mix",
        "request_overrides",
    }
)
_BASE_DAW_ACTION_TYPES = frozenset(
    {
        "tutorial",
        "clarify",
        "clip_edit",
        "row_group_edit",
        "row_color_edit",
        "effect_edit",
        "automation_edit",
        "midi_compose",
        "stem_separate",
        "role_override",
        "audio_enhance",
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
_ALLOWED_MIX_EXECUTION_PROFILES = frozenset(
    {
        "producer_safe",
        "creative_bold",
        "experimental_extreme",
    }
)
_ALLOWED_MIX_AUDIBILITY = frozenset(
    {
        "subtle",
        "noticeable",
        "obvious",
        "extreme",
    }
)
_ALLOWED_MIX_REFERENCE_MODES = frozenset(
    {
        "tone",
        "loudness",
        "width",
        "glue",
        "full_mix",
    }
)
_ALLOWED_MIX_REFERENCE_CLOSENESS = frozenset(
    {
        "loose",
        "balanced",
        "close",
    }
)
_TOOL_TEXT_LEAK_MARKERS = (
    "mix_model_request",
    "daw_assistant_actions",
    "informational_response",
    '"assistant_message"',
    '"row_index"',
    '"target_id"',
    "project snapshot",
    "selection snapshot",
    "project_snapshot",
    "selection_snapshot",
    "library_snapshot",
    "pending_mix_proposal",
    "isempty = true",
    "isempty = false",
    "isempty=true",
    "isempty=false",
    "clip_index",
    "clip_indices",
    "row_index:",
)
_INVALID_STRUCTURED_OUTPUT_MESSAGE = (
    "I couldn't complete that request just now. Please try again."
)

init_sentry("mixroom-llm-proxy")


def _normalize_mix_goal_type(_: Any) -> str:
    # Compatibility shim: legacy model outputs sometimes leak the primary sonic
    # intent into goal.type ("eq", "reverb", etc). On this wire format there is
    # only one valid goal type, and shipped clients expect it.
    return "mix_request"


def _normalize_mix_execution_profile(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in _ALLOWED_MIX_EXECUTION_PROFILES:
        return normalized
    return "producer_safe"


def _normalize_mix_audibility(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in _ALLOWED_MIX_AUDIBILITY:
        return normalized
    return "noticeable"


def _normalize_mix_style_tags(value: Any) -> list[str]:
    raw_values = value if isinstance(value, list) else ([value] if isinstance(value, str) else [])
    out: list[str] = []
    seen: set[str] = set()
    for item in raw_values:
        normalized = str(item or "").strip().lower()
        if not normalized or normalized == "null":
            continue
        canonical = re.sub(r"\s+", "_", normalized)
        if not canonical or len(canonical) > 40 or canonical in seen:
            continue
        seen.add(canonical)
        out.append(canonical)
        if len(out) >= 8:
            break
    return out


def _normalize_mix_reference_target(value: Any) -> Dict[str, Any] | None:
    if not isinstance(value, dict):
        return None

    normalized: Dict[str, Any] = {}
    raw_row_index = value.get("row_index")
    if isinstance(raw_row_index, (int, float)):
        row_index = int(raw_row_index)
        if row_index >= 0:
            normalized["row_index"] = row_index
    elif value.get("prefer_selected") is True:
        normalized["prefer_selected"] = True
    else:
        return None

    raw_confidence = value.get("confidence")
    normalized["confidence"] = (
        max(0.0, min(1.0, float(raw_confidence)))
        if isinstance(raw_confidence, (int, float))
        else 0.5
    )
    return normalized


def _normalize_mix_reference_mode(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in _ALLOWED_MIX_REFERENCE_MODES:
        return normalized
    return "full_mix"


def _normalize_mix_reference_closeness(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in _ALLOWED_MIX_REFERENCE_CLOSENESS:
        return normalized
    return "balanced"


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

    parameter_name = _env_value("LLM_API_KEY_PARAMETER_NAME", "OPENAI_API_KEY_PARAMETER_NAME")
    secret_arn = _env_value("LLM_API_KEY_SECRET_ARN", "OPENAI_API_KEY_SECRET_ARN")
    if not parameter_name and not secret_arn:
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
        raise RuntimeError("boto3 is required to read backend secret values.")

    if parameter_name:
        client = boto3.client("ssm")
        result = client.get_parameter(Name=parameter_name, WithDecryption=True)
        parameter = result.get("Parameter") or {}
        secret_string = str(parameter.get("Value") or "")
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

        raise ValueError("LLM API key SSM parameter must contain a string or JSON object.")

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


def _is_v3_responses_path(path: str) -> bool:
    return str(path or "").rstrip("/").endswith("/v1/llm/v3/responses")


def _v3_enabled() -> bool:
    return _env_value("AI_V3_ENABLED", default="true").lower() == "true"


def _configured_v3_model() -> str:
    return _env_value("AI_V3_MODEL", default="gpt-5.6-luna")


def _configured_v3_reasoning_effort() -> str:
    normalized = _env_value("AI_V3_REASONING_EFFORT", default="low").lower()
    supported = {"none", "minimal", "low", "medium", "high", "xhigh"}
    return normalized if normalized in supported else "low"


def _validate_v3_request_body(body: Dict[str, Any]) -> None:
    if any(key in body for key in _STRUCTURED_MIXROOM_FIELDS):
        raise ValueError("V3 requires an OpenAI-compatible planner request.")
    tools = body.get("tools")
    if not isinstance(tools, list) or len(tools) != 1:
        raise ValueError("V3 requires exactly one planner tool.")
    tool = tools[0]
    if (
        not isinstance(tool, dict)
        or str(tool.get("type") or "").strip() != "function"
        or str(tool.get("name") or "").strip() != "submit_plan_v3"
    ):
        raise ValueError("V3 requires the submit_plan_v3 tool.")
    tool_choice = body.get("tool_choice")
    if (
        not isinstance(tool_choice, dict)
        or str(tool_choice.get("type") or "").strip() != "function"
        or str(tool_choice.get("name") or "").strip() != "submit_plan_v3"
    ):
        raise ValueError("V3 requires submit_plan_v3 tool choice.")
    if body.get("parallel_tool_calls") is not False:
        raise ValueError("V3 parallel tool calls must be disabled.")
    if body.get("store") is not True:
        raise ValueError("V3 provider storage must be enabled.")


def _provider_name() -> str:
    return _env_value("LLM_PROVIDER", default=DEFAULT_PROVIDER).lower()


def _request_timeout_seconds() -> int:
    raw = _env_value("LLM_TIMEOUT_SECONDS", "OPENAI_TIMEOUT_SECONDS", default="30")
    try:
        value = int(raw)
    except ValueError:
        return 30
    return max(1, value)


def _conversation_state_table_name() -> str:
    return _env_value("OPENAI_CONVERSATION_STATE_TABLE")


def _conversation_state_mode_from_body(body: Dict[str, Any]) -> str:
    normalized = str(body.get("conversation_state_mode") or "").strip().lower()
    if normalized in {"openai_conversation", "openai_conversation_seeded"}:
        return normalized
    return "manual_history"


def _uses_openai_conversation_state(mode: str) -> bool:
    return mode in {"openai_conversation", "openai_conversation_seeded"}


def _conversation_state_table_client() -> Any | None:
    table_name = _conversation_state_table_name()
    if not table_name or boto3 is None:
        return None

    global _conversation_state_table
    if _conversation_state_table is None:
        _conversation_state_table = boto3.resource("dynamodb").Table(table_name)
    return _conversation_state_table


def _conversation_safe_key_part(value: str, fallback: str) -> str:
    normalized = str(value or "").strip()
    return normalized if normalized else fallback


def _conversation_session_key(
    *,
    user_id: str,
    project_id: str,
    ai_feature: str,
    conversation_session_id: str,
) -> str:
    parts = [
        _conversation_safe_key_part(user_id, "anonymous"),
        _conversation_safe_key_part(project_id, "no_project"),
        _conversation_safe_key_part(ai_feature, "ai_chat"),
        _conversation_safe_key_part(conversation_session_id, "default_session"),
    ]
    return "#".join(parts)


def _conversation_mapping_key(
    *,
    user_id: str,
    project_id: str,
    ai_feature: str,
    conversation_session_id: str,
    runtime_config_fingerprint: str,
) -> str:
    return "#".join(
        [
            _conversation_session_key(
                user_id=user_id,
                project_id=project_id,
                ai_feature=ai_feature,
                conversation_session_id=conversation_session_id,
            ),
            _conversation_safe_key_part(
                runtime_config_fingerprint,
                "runtime_unknown",
            ),
        ]
    )


def _short_hash(value: str, *, length: int = 16) -> str:
    return hashlib.sha256(value.strip().encode("utf-8")).hexdigest()[:length]


def _utc_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _conversation_metadata(
    *,
    user_id: str,
    project_id: str,
    ai_feature: str,
    conversation_state_mode: str,
    conversation_session_id: str,
    runtime_config_fingerprint: str,
    seed_hash: str = "",
) -> Dict[str, Any]:
    return _compact_dict(
        {
            "source": "mixroom_llm_proxy",
            "conversation_state_mode": conversation_state_mode,
            "user_hash": _short_hash(user_id),
            "project_hash": _short_hash(project_id or "no_project"),
            "ai_feature": ai_feature,
            "session_hash": _short_hash(conversation_session_id or "default_session"),
            "runtime_config_fingerprint": runtime_config_fingerprint,
            "seed_hash": seed_hash,
        }
    )


def _ensure_openai_conversation_id(
    *,
    api_key: str,
    user_id: str,
    project_id: str,
    ai_feature: str,
    conversation_state_mode: str,
    conversation_session_id: str,
    runtime_config_fingerprint: str,
    request_body: Dict[str, Any],
) -> tuple[str, bool]:
    table = _conversation_state_table_client()
    if table is None:
        return "", False

    session_key = _conversation_session_key(
        user_id=user_id,
        project_id=project_id,
        ai_feature=ai_feature,
        conversation_session_id=conversation_session_id,
    )
    mapping_key = _conversation_mapping_key(
        user_id=user_id,
        project_id=project_id,
        ai_feature=ai_feature,
        conversation_session_id=conversation_session_id,
        runtime_config_fingerprint=runtime_config_fingerprint,
    )
    existing = table.get_item(Key={"mapping_key": mapping_key}).get("Item")
    if isinstance(existing, dict):
        existing_id = str(existing.get("openai_conversation_id") or "").strip()
        if existing_id:
            return existing_id, False

    seed_hash = str(request_body.get("openai_conversation_seed_hash") or "").strip()
    seed_items = request_body.get("openai_conversation_seed_items")
    if not isinstance(seed_items, list):
        seed_items = []
    conversation_id = create_openai_conversation(
        api_key=api_key,
        metadata=_conversation_metadata(
            user_id=user_id,
            project_id=project_id,
            ai_feature=ai_feature,
            conversation_state_mode=conversation_state_mode,
            conversation_session_id=conversation_session_id,
            runtime_config_fingerprint=runtime_config_fingerprint,
            seed_hash=seed_hash,
        ),
        seed_items=seed_items,
        timeout_seconds=_request_timeout_seconds(),
    )
    now = _utc_timestamp()
    table.put_item(
        Item={
            "mapping_key": mapping_key,
            "session_key": session_key,
            "openai_conversation_id": conversation_id,
            "conversation_state_mode": conversation_state_mode,
            "user_id": user_id,
            "project_id": project_id,
            "ai_feature": ai_feature,
            "conversation_session_id": conversation_session_id,
            "runtime_config_fingerprint": runtime_config_fingerprint,
            "seed_hash": seed_hash,
            "created_at": now,
            "updated_at": now,
        }
    )
    return conversation_id, True


def _latest_openai_conversation_id_for_session(
    *,
    user_id: str,
    project_id: str,
    ai_feature: str,
    conversation_session_id: str,
) -> str:
    table = _conversation_state_table_client()
    if table is None or not conversation_session_id.strip():
        return ""

    try:
        from boto3.dynamodb.conditions import Key
    except Exception:
        return ""

    session_key = _conversation_session_key(
        user_id=user_id,
        project_id=project_id,
        ai_feature=ai_feature,
        conversation_session_id=conversation_session_id,
    )
    result = table.query(
        IndexName="session_updated_at_idx",
        KeyConditionExpression=Key("session_key").eq(session_key),
        ScanIndexForward=False,
        Limit=1,
    )
    items = result.get("Items")
    if not isinstance(items, list) or not items:
        return ""
    item = items[0]
    if not isinstance(item, dict):
        return ""
    return str(item.get("openai_conversation_id") or "").strip()


def _conversation_execution_event_text(body: Dict[str, Any]) -> str:
    action_types = body.get("action_types")
    if not isinstance(action_types, list):
        action_types = []
    normalized_actions = [
        str(action).strip()
        for action in action_types
        if isinstance(action, str) and action.strip()
    ][:24]

    failed_actions = body.get("failed_actions")
    if not isinstance(failed_actions, list):
        failed_actions = []
    normalized_failed = [
        str(action).strip()
        for action in failed_actions
        if isinstance(action, str) and action.strip()
    ][:24]

    summary = str(body.get("summary") or "").strip()[:2000]
    prompt_trace_id = str(body.get("prompt_trace_id") or "").strip()
    applied = body.get("applied")

    return "\n".join(
        [
            "MIXROOM DAW EXECUTION RESULT",
            f"prompt_trace_id: {prompt_trace_id}",
            f"applied: {bool(applied)}",
            f"action_types: {', '.join(normalized_actions) if normalized_actions else 'none'}",
            f"failed_actions: {', '.join(normalized_failed) if normalized_failed else 'none'}",
            f"summary: {summary or 'No additional execution summary was provided.'}",
            "",
            "Use this compact result only as prior-turn execution memory. Fresh PROJECT_SNAPSHOT remains authoritative.",
        ]
    ).strip()


def _handle_conversation_event(
    *,
    body: Dict[str, Any],
    user_id: str,
) -> Dict[str, Any]:
    event_type = str(body.get("event_type") or "").strip()
    if event_type != "daw_execution_result":
        return json_response(400, {"error": "Unsupported conversation event type."})

    conversation_state_mode = _conversation_state_mode_from_body(body)
    if not _uses_openai_conversation_state(conversation_state_mode):
        return json_response(200, {"ok": True, "appended": False, "noop": True})

    project_id = str(body.get("project_id") or "").strip()
    raw_ai_feature = str(body.get("ai_feature") or "ai_chat").strip() or "ai_chat"
    try:
        ai_feature = validate_feature(raw_ai_feature)
    except ValueError as error:
        return json_response(400, {"error": str(error)})

    conversation_session_id = str(body.get("conversation_session_id") or "").strip()
    if not conversation_session_id:
        return json_response(200, {"ok": True, "appended": False, "noop": True})

    conversation_id = _latest_openai_conversation_id_for_session(
        user_id=user_id,
        project_id=project_id,
        ai_feature=ai_feature,
        conversation_session_id=conversation_session_id,
    )
    if not conversation_id:
        return json_response(200, {"ok": True, "appended": False, "noop": True})

    api_key = _load_api_key(DEFAULT_PROVIDER)
    if not api_key:
        return json_response(500, {"error": "LLM API key is not configured."})

    appended = append_openai_conversation_items(
        api_key=api_key,
        conversation_id=conversation_id,
        items=[
            {
                "type": "message",
                "role": "developer",
                "content": [
                    {
                        "type": "input_text",
                        "text": _conversation_execution_event_text(body),
                    }
                ],
            }
        ],
        timeout_seconds=_request_timeout_seconds(),
    )
    return json_response(
        200,
        {
            "ok": True,
            "appended": appended,
            "openai_conversation_id_hash": _short_hash(conversation_id),
        },
    )


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


def _client_status_code_for_upstream_error(status_code: int) -> int:
    # Provider 429s are transient upstream throttles, not Mixroom prompt quota
    # failures. Returning them as 429 makes existing clients show prompt-limit
    # copy, so expose them as service-unavailable responses instead.
    if status_code == 429:
        return 503
    return status_code


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
    conversation_contract_hash = str(
        request_body.get("openai_conversation_contract_hash") or ""
    ).strip()
    if conversation_contract_hash:
        system_prompt_hash = conversation_contract_hash
    else:
        system_prompt = str(
            request_body.get("instructions") or runtime_config.get("system_prompt") or ""
        )
        system_prompt_hash = hashlib.sha256(system_prompt.encode("utf-8")).hexdigest()[
            :16
        ]
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
    if re.search(r"\bisempty\s*=\s*(true|false)\b", lower):
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


def _parse_action_int(raw: Any) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    if isinstance(raw, str):
        try:
            return int(raw.strip())
        except ValueError:
            return None
    return None


def _parse_action_float(raw: Any) -> float | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str):
        try:
            return float(raw.strip())
        except ValueError:
            return None
    return None


def _measure_index_to_start_beat(raw: Any) -> float | None:
    measure = _parse_action_float(raw)
    if measure is None:
        return None
    return (measure - 1.0) * 4.0


def _measures_to_beats(raw: Any) -> float | None:
    measures = _parse_action_float(raw)
    if measures is None:
        return None
    return measures * 4.0


def _normalize_midi_velocity(raw: Any) -> float | None:
    parsed = _parse_action_float(raw)
    if parsed is None:
        return None
    if parsed > 1.0:
        return max(0.0, min(1.0, parsed / 127.0))
    return max(0.0, min(1.0, parsed))


def _midi_pitch_from_raw(raw: Any, *, fallback_octave: int = 3) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        return int(raw)
    if not isinstance(raw, str):
        return None
    token = raw.strip()
    if not token:
        return None
    try:
        return int(token)
    except ValueError:
        pass

    match = re.fullmatch(r"([A-Ga-g])([#b]?)(-?\d+)?", token)
    if not match:
        return None
    note_name = (match.group(1) or "").upper()
    accidental = match.group(2) or ""
    octave = int(match.group(3) or fallback_octave)
    semitone = {
        "C": 0,
        "D": 2,
        "E": 4,
        "F": 5,
        "G": 7,
        "A": 9,
        "B": 11,
    }.get(note_name)
    if semitone is None:
        return None
    if accidental == "#":
        semitone += 1
    elif accidental == "b":
        semitone -= 1
    return (octave + 1) * 12 + semitone


def _is_valid_midi_note_payload(note: Dict[str, Any]) -> bool:
    pitch = note.get("pitch")
    chord_pitches = note.get("pitches")
    start_beat = note.get("start_beat")
    length_beats = note.get("length_beats")
    has_single_pitch = isinstance(pitch, int) and 0 <= pitch <= 127
    has_chord_pitches = (
        isinstance(chord_pitches, list)
        and any(isinstance(value, int) and 0 <= value <= 127 for value in chord_pitches)
    )
    if not has_single_pitch and not has_chord_pitches:
        return False
    if not isinstance(start_beat, (int, float)):
        return False
    if not isinstance(length_beats, (int, float)) or float(length_beats) <= 0.0:
        return False
    return True


def _normalize_midi_note_payload(raw_note: Dict[str, Any]) -> Dict[str, Any]:
    note = dict(raw_note)

    pitch = _midi_pitch_from_raw(
        note.get("pitch")
        or note.get("midi")
        or note.get("note")
        or note.get("note_name")
    )
    if pitch is not None:
        note["pitch"] = max(0, min(127, pitch))

    raw_chord_pitches = note.get("pitches")
    if isinstance(raw_chord_pitches, list):
        normalized_chord_pitches = []
        for raw_pitch in raw_chord_pitches:
            chord_pitch = _midi_pitch_from_raw(raw_pitch)
            if chord_pitch is None:
                continue
            normalized_chord_pitches.append(max(0, min(127, chord_pitch)))
        if normalized_chord_pitches:
            note["pitches"] = normalized_chord_pitches

    start_beat = _parse_action_float(
        note.get("start_beat")
        or note.get("startBeat")
        or note.get("time_beats")
        or note.get("timeBeats")
        or note.get("time_beat")
        or note.get("timeBeat")
        or note.get("absolute_beat")
        or note.get("absoluteBeat")
        or note.get("timeline_beat")
        or note.get("timelineBeat")
        or note.get("at_beat")
        or note.get("atBeat")
        or note.get("offset_beats")
        or note.get("offsetBeats")
        or note.get("start")
    )
    if start_beat is None:
        measure = _parse_action_float(
            note.get("start_measure")
            or note.get("startMeasure")
            or note.get("start_bar")
            or note.get("startBar")
            or note.get("measure")
            or note.get("bar")
        )
        beat_in_measure = _parse_action_float(
            note.get("beat_in_measure")
            or note.get("beatInMeasure")
            or note.get("beat")
            or note.get("beat_index")
            or note.get("beatIndex")
        )
        if measure is not None:
            clamped_measure = max(1.0, measure)
            within_measure = (
                beat_in_measure - 1.0
                if beat_in_measure is not None and beat_in_measure > 0.0
                else 0.0
            )
            start_beat = ((clamped_measure - 1.0) * 4.0) + within_measure
        else:
            start_beat = beat_in_measure
    if start_beat is not None:
        note["start_beat"] = start_beat

    length_beats = _parse_action_float(
        note.get("length_beats")
        or note.get("lengthBeats")
        or note.get("lengthBeat")
        or note.get("length")
        or note.get("duration_beats")
        or note.get("durationBeats")
        or note.get("duration")
    )
    if length_beats is None:
        length_beats = _measures_to_beats(
            note.get("duration_measures")
            or note.get("durationMeasures")
            or note.get("length_measures")
            or note.get("lengthMeasures")
            or note.get("duration_bars")
            or note.get("durationBars")
        )
    if length_beats is not None:
        note["length_beats"] = length_beats

    velocity = _normalize_midi_velocity(note.get("velocity"))
    if velocity is not None:
        note["velocity"] = velocity

    return note


def _normalize_midi_notes_payload(raw_notes: Any) -> list[dict[str, Any]]:
    if not isinstance(raw_notes, list):
        return []
    normalized: list[dict[str, Any]] = []
    for raw_note in raw_notes:
        if not isinstance(raw_note, dict):
            continue
        note = _normalize_midi_note_payload(dict(raw_note))
        if _is_valid_midi_note_payload(note):
            normalized.append(note)
    return normalized


def _normalize_sample_insert_item(raw_item: Dict[str, Any]) -> Dict[str, Any]:
    item = dict(raw_item)
    target = item.get("target")
    normalized_target = dict(target) if isinstance(target, dict) else {}
    item["target"] = normalized_target

    library_path = str(
        item.get("library_path")
        or normalized_target.get("library_path")
        or item.get("asset_path")
        or normalized_target.get("asset_path")
        or ""
    ).strip()
    if library_path:
        item["library_path"] = library_path

    row_index = _parse_action_int(item.get("row_index") or normalized_target.get("row_index"))
    if row_index is not None and row_index >= 0:
        item["row_index"] = row_index
        normalized_target.setdefault("row_index", row_index)

    for key in ("start_ms", "start_measure", "start_beat"):
        value = _parse_action_float(item.get(key) or normalized_target.get(key))
        if value is not None:
            item[key] = value

    return item



_ALLOWED_CLIP_EDIT_OPERATIONS = frozenset(
    {
        "trim",
        "auto_trim",
        "cut",
        "stretch",
        "pitch_shift",
        "glue",
        "move",
        "tempo_follow",
        "auto_bpm_align",
        "tempo_detect_set_project",
        "duplicate",
        "delete",
        "dialog_cleanup",
        "dialog_remove_range",
        "dialog_tighten_pauses",
        "dialog_lift_quiet",
    }
)
_ALLOWED_ROW_GROUP_EDIT_OPERATIONS = frozenset(
    {"create", "remove_row", "toggle_collapsed"}
)
_ALLOWED_ROW_COLOR_EDIT_OPERATIONS = frozenset({"set", "clear"})
_ALLOWED_EFFECT_EDIT_OPERATIONS = frozenset(
    {"add", "remove", "bypass", "unbypass", "toggle_bypass"}
)
_ALLOWED_AUTOMATION_EDIT_OPERATIONS = frozenset(
    {
        "set_points",
        "add_ramp",
        "clear",
        "create_clip",
        "duplicate_clip",
        "move_clip",
        "delete_clip",
        "clear_clips",
        "mute_clip",
        "unmute_clip",
        "toggle_clip_mute",
        "set_clip_points",
        "make_unique_clip",
        "apply_template",
    }
)
_ALLOWED_MIDI_COMPOSE_OPERATIONS = frozenset(
    {
        "create_clip",
        "compose_bassline",
        "compose_pattern",
        "replace_notes",
        "append_notes",
        "transpose_notes",
        "chop_notes",
        "convert_audio_to_midi",
    }
)
_ALLOWED_STEM_SEPARATE_OPERATIONS = frozenset({"vocal_instrumental"})
_ALLOWED_ROLE_OVERRIDE_OPERATIONS = frozenset({"set", "clear"})
_ALLOWED_PROJECT_EDIT_OPERATIONS = frozenset({"set_tempo"})
_ALLOWED_SAMPLE_INSERT_OPERATIONS = frozenset(
    {"insert_audio_clips", "replace_audio_clips"}
)


def _client_capabilities_from_context(client_context: Dict[str, Any] | None) -> set[str]:
    if not isinstance(client_context, dict):
        return set()
    raw = client_context.get("ai_capabilities")
    if not isinstance(raw, list):
        return set()
    capabilities: set[str] = set()
    for item in raw:
        if isinstance(item, str) and item.strip():
            capabilities.add(item.strip())
    return capabilities


def _allowed_daw_action_types(client_capabilities: set[str]) -> set[str]:
    allowed = set(_BASE_DAW_ACTION_TYPES)
    if "daw.project_edit.set_tempo" in client_capabilities:
        allowed.add("project_edit")
    if "daw.sample_insert.library" in client_capabilities:
        allowed.add("sample_insert")
    return allowed


def _allowed_midi_compose_operations(client_capabilities: set[str]) -> set[str]:
    allowed = set(_ALLOWED_MIDI_COMPOSE_OPERATIONS)
    if "daw.midi_compose.transpose_notes" not in client_capabilities:
        allowed.discard("transpose_notes")
    if "daw.midi_compose.audio_to_midi" not in client_capabilities:
        allowed.discard("convert_audio_to_midi")
    return allowed


def _normalize_clip_edit_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "split": "cut",
        "split_clip": "cut",
        "cut_clip": "cut",
        "resize": "stretch",
        "resize_clip": "stretch",
        "glue_clips": "glue",
        "merge": "glue",
        "merge_clip": "glue",
        "merge_clips": "glue",
        "consolidate": "glue",
        "consolidate_clip": "glue",
        "consolidate_clips": "glue",
        "bounce_clip": "glue",
        "bounce_clips": "glue",
        "move_clip": "move",
        "reposition": "move",
        "shift": "move",
        "nudge": "move",
        "copy": "duplicate",
        "copy_clip": "duplicate",
        "remove": "delete",
        "remove_clip": "delete",
        "delete_clip": "delete",
        "tempo_follow_project": "tempo_follow",
        "align_tempo": "auto_bpm_align",
        "align_to_project_tempo": "auto_bpm_align",
        "detect_tempo_set_project": "tempo_detect_set_project",
    }
    return aliases.get(token, token)


def _normalize_effect_edit_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "delete": "remove",
        "remove": "remove",
        "delete_effect": "remove",
        "remove_effect": "remove",
        "take_out": "remove",
        "insert": "add",
        "ensure": "add",
        "ensure_effect": "add",
        "add_effect": "add",
        "insert_effect": "add",
        "disable": "bypass",
        "mute": "bypass",
        "enable": "unbypass",
        "unmute": "unbypass",
        "toggle": "toggle_bypass",
    }
    return aliases.get(token, token)


def _normalize_automation_edit_operation(raw: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")


def _normalize_project_edit_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "set_bpm": "set_tempo",
        "change_bpm": "set_tempo",
        "set_project_bpm": "set_tempo",
        "change_project_bpm": "set_tempo",
        "set_project_tempo": "set_tempo",
        "change_tempo": "set_tempo",
    }
    return aliases.get(token, token)


def _normalize_sample_insert_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "insert_audio_clip": "insert_audio_clips",
        "insert_sample": "insert_audio_clips",
        "insert_samples": "insert_audio_clips",
        "add_sample": "insert_audio_clips",
        "add_samples": "insert_audio_clips",
        "insert_library_audio": "insert_audio_clips",
        "replace_audio_clip": "replace_audio_clips",
        "replace_audio": "replace_audio_clips",
        "replace_sample": "replace_audio_clips",
        "replace_samples": "replace_audio_clips",
        "swap_sample": "replace_audio_clips",
        "swap_samples": "replace_audio_clips",
    }
    return aliases.get(token, token)


def _normalize_midi_compose_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "create": "create_clip",
        "create_clip": "create_clip",
        "new_clip": "create_clip",
        "new_midi_clip": "create_clip",
        "compose": "compose_pattern",
        "compose_notes": "compose_pattern",
        "write_pattern": "compose_pattern",
        "generate_pattern": "compose_pattern",
        "make_pattern": "compose_pattern",
        "compose_bass": "compose_bassline",
        "write_bassline": "compose_bassline",
        "generate_bassline": "compose_bassline",
        "make_bassline": "compose_bassline",
        "replace": "replace_notes",
        "overwrite_notes": "replace_notes",
        "set_notes": "replace_notes",
        "append": "append_notes",
        "add_notes": "append_notes",
        "extend_notes": "append_notes",
        "transpose": "transpose_notes",
        "transpose_note": "transpose_notes",
        "transpose_notes": "transpose_notes",
        "shift_pitch": "transpose_notes",
        "pitch_shift": "transpose_notes",
        "octave_up": "transpose_notes",
        "octave_down": "transpose_notes",
        "audio_to_midi": "convert_audio_to_midi",
        "convert_to_midi": "convert_audio_to_midi",
        "transcribe_audio": "convert_audio_to_midi",
        "extract_midi": "convert_audio_to_midi",
        "chop": "chop_notes",
        "chop_note": "chop_notes",
        "note_chop": "chop_notes",
        "note_chopper": "chop_notes",
        "splice_notes": "chop_notes",
        "slice_notes": "chop_notes",
        "split_notes": "chop_notes",
        "grid_chop": "chop_notes",
        "ratchet": "chop_notes",
        "stutter": "chop_notes",
    }
    return aliases.get(token, token)


def _normalize_role_override_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    if token in {"clear", "remove", "unset", "delete"}:
        return "clear"
    return token


def _normalize_row_group_edit_operation(raw: Any) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", str(raw or "").strip().lower()).strip("_")
    aliases = {
        "group": "create",
        "group_rows": "create",
        "create_group": "create",
        "create_row_group": "create",
        "make_group": "create",
        "make_row_group": "create",
        "ungroup_row": "remove_row",
        "remove_from_group": "remove_row",
        "remove_row_from_group": "remove_row",
        "toggle": "toggle_collapsed",
        "fold": "toggle_collapsed",
        "unfold": "toggle_collapsed",
        "collapse": "toggle_collapsed",
        "expand": "toggle_collapsed",
        "toggle_group": "toggle_collapsed",
        "toggle_row_group": "toggle_collapsed",
    }
    return aliases.get(token, token)


def _is_plain_audio_pitch_request(user_text: str) -> bool:
    text = str(user_text or "").lower()
    if not re.search(r"\b(pitch|key|semitone|semitones|half[- ]step|transpose)\b", text):
        return False
    return not re.search(
        r"\b(automation|automate|curve|effect|plugin|insert|add\s+pitch\s+shift)\b",
        text,
    )


def _pitch_delta_from_user_text(user_text: str) -> float | None:
    text = str(user_text or "").lower()
    if re.search(r"\b(?:one|1|a)\s+(?:key|semitone|half[- ]step)\b", text):
        return -1.0 if re.search(r"\b(lower|down|decrease|drop)\b", text) else 1.0

    signed = re.search(r"([+-]\s*\d+(?:\.\d+)?)\s*(?:semitones?|keys?|half[- ]steps?)\b", text)
    if signed:
        try:
            return float(signed.group(1).replace(" ", ""))
        except ValueError:
            return None

    amount = re.search(r"\b(\d+(?:\.\d+)?)\s*(?:semitones?|keys?|half[- ]steps?)\b", text)
    if amount:
        try:
            value = float(amount.group(1))
        except ValueError:
            return None
        return -value if re.search(r"\b(lower|down|decrease|drop)\b", text) else value
    return None


def _looks_like_pitch_shift_effect(data: Dict[str, Any], target: Dict[str, Any]) -> bool:
    fields = (
        data.get("effect_name"),
        data.get("plugin_name"),
        data.get("effect_name_contains"),
        data.get("plugin_name_contains"),
        target.get("effect_name"),
        target.get("plugin_name"),
        target.get("effect_name_contains"),
        target.get("plugin_name_contains"),
    )
    haystack = " ".join(str(value or "").lower() for value in fields)
    return "pitch" in haystack and ("shift" in haystack or "shifter" in haystack)


def _looks_like_pitch_automation(data: Dict[str, Any], target: Dict[str, Any]) -> bool:
    fields = (
        data.get("param_name"),
        data.get("parameter"),
        data.get("param_name_contains"),
        target.get("param_name"),
        target.get("parameter"),
        target.get("param_name_contains"),
        data.get("effect_name"),
        data.get("plugin_name"),
        target.get("effect_name"),
        target.get("plugin_name"),
    )
    haystack = " ".join(str(value or "").lower() for value in fields)
    return "pitch" in haystack


def _retarget_plain_pitch_action_if_needed(
    *,
    action_type: str,
    normalized_data: Dict[str, Any],
    normalized_target: Dict[str, Any],
    user_text: str,
    client_capabilities: set[str],
) -> tuple[str, Dict[str, Any], Dict[str, Any]]:
    if "daw.clip_edit.pitch_shift" not in client_capabilities:
        return action_type, normalized_data, normalized_target
    if not _is_plain_audio_pitch_request(user_text):
        return action_type, normalized_data, normalized_target
    if action_type == "effect_edit":
        if not _looks_like_pitch_shift_effect(normalized_data, normalized_target):
            return action_type, normalized_data, normalized_target
    elif action_type == "automation_edit":
        if not _looks_like_pitch_automation(normalized_data, normalized_target):
            return action_type, normalized_data, normalized_target
    else:
        return action_type, normalized_data, normalized_target

    semitones = (
        _parse_action_float(normalized_data.get("semitones"))
        or _parse_action_float(normalized_target.get("semitones"))
        or _parse_action_float(normalized_data.get("delta_semitones"))
        or _parse_action_float(normalized_target.get("delta_semitones"))
        or _parse_action_float(normalized_data.get("pitch_semitones"))
        or _parse_action_float(normalized_target.get("pitch_semitones"))
        or _pitch_delta_from_user_text(user_text)
    )
    if semitones is None:
        return action_type, normalized_data, normalized_target

    target = dict(normalized_target)
    if not any(
        key in target
        for key in (
            "clip_index",
            "clip_indices",
            "row_index",
            "label_contains",
            "file_name_contains",
            "scope",
        )
    ) and re.search(
        r"\b(background|backing|instrumental|music|beat)\b",
        str(user_text or "").lower(),
    ):
        target["label_contains"] = "Instrumental"

    return (
        "clip_edit",
        {
            "operation": "pitch_shift",
            "delta_semitones": semitones,
            "target": target,
        },
        target,
    )


def _normalize_daw_action_payloads(
    actions: list[dict[str, Any]],
    *,
    user_text: str,
    client_capabilities: set[str],
) -> list[dict[str, Any]]:
    allowed_action_types = _allowed_daw_action_types(client_capabilities)
    allowed_midi_operations = _allowed_midi_compose_operations(client_capabilities)
    normalized_actions: list[dict[str, Any]] = []
    for action in actions:
        normalized_action = dict(action)
        data = normalized_action.get("data")
        if not isinstance(data, dict):
            continue
        normalized_data = dict(data)
        target = normalized_data.get("target")
        if isinstance(target, dict):
            normalized_target = dict(target)
            normalized_data["target"] = normalized_target
        else:
            normalized_target = {}
            normalized_data["target"] = normalized_target

        parsed_row_index = _parse_action_int(normalized_target.get("row_index"))
        if parsed_row_index is not None and parsed_row_index >= 0:
            normalized_target["row_index"] = parsed_row_index

        action_type = str(normalized_action.get("type") or "").strip().lower()
        action_type, normalized_data, normalized_target = (
            _retarget_plain_pitch_action_if_needed(
                action_type=action_type,
                normalized_data=normalized_data,
                normalized_target=normalized_target,
                user_text=user_text,
                client_capabilities=client_capabilities,
            )
        )
        normalized_action["type"] = action_type
        if action_type not in allowed_action_types:
            continue
        if action_type == "clarify":
            question = str(normalized_data.get("question") or "").strip()
            if not question:
                continue
            options = normalized_data.get("options")
            if isinstance(options, list):
                normalized_data["options"] = [
                    str(option).strip()
                    for option in options
                    if str(option).strip()
                ]
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
            topic = str(normalized_data.get("topic") or "").strip()
            steps = normalized_data.get("steps")
            if not topic and not isinstance(steps, list):
                continue

        if action_type == "clip_edit":
            operation = _normalize_clip_edit_operation(normalized_data.get("operation"))
            if operation not in _ALLOWED_CLIP_EDIT_OPERATIONS:
                continue
            if (
                operation == "pitch_shift"
                and "daw.clip_edit.pitch_shift" not in client_capabilities
            ):
                continue
            normalized_data["operation"] = operation
            if operation == "pitch_shift":
                semitones = _parse_action_float(
                    normalized_data.get("semitones")
                    or normalized_target.get("semitones")
                    or normalized_data.get("delta_semitones")
                    or normalized_target.get("delta_semitones")
                    or normalized_data.get("pitch_semitones")
                    or normalized_target.get("pitch_semitones")
                    or normalized_data.get("new_pitch_semitones")
                    or normalized_target.get("new_pitch_semitones")
                )
                if semitones is None:
                    continue
                normalized_data["delta_semitones"] = semitones
            if normalized_target is not None and _user_requested_global_clip_scope(user_text):
                normalized_target["scope"] = "all"
                normalized_target.pop("clip_index", None)
                normalized_target.pop("clip_indices", None)
                normalized_target.pop("row_index", None)
                normalized_target.pop("prefer_selected", None)
                normalized_data["target"] = normalized_target
        elif action_type == "row_group_edit":
            operation = _normalize_row_group_edit_operation(
                normalized_data.get("operation")
            )
            if operation not in _ALLOWED_ROW_GROUP_EDIT_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "row_color_edit":
            operation = re.sub(
                r"[^a-z0-9]+", "_",
                str(normalized_data.get("operation") or "set").strip().lower(),
            ).strip("_")
            if operation in {"remove", "unset", "delete"}:
                operation = "clear"
            if operation not in _ALLOWED_ROW_COLOR_EDIT_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "effect_edit":
            operation = _normalize_effect_edit_operation(normalized_data.get("operation"))
            if operation not in _ALLOWED_EFFECT_EDIT_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "automation_edit":
            operation = _normalize_automation_edit_operation(
                normalized_data.get("operation")
            )
            if operation not in _ALLOWED_AUTOMATION_EDIT_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "project_edit":
            operation = _normalize_project_edit_operation(normalized_data.get("operation"))
            if operation not in _ALLOWED_PROJECT_EDIT_OPERATIONS:
                continue
            tempo = _parse_action_float(
                normalized_data.get("tempo_bpm")
                or normalized_target.get("tempo_bpm")
                or normalized_data.get("bpm")
                or normalized_target.get("bpm")
            )
            if tempo is None or tempo <= 0.0:
                continue
            normalized_data["operation"] = operation
            normalized_data["tempo_bpm"] = tempo
        elif action_type == "sample_insert":
            operation = _normalize_sample_insert_operation(normalized_data.get("operation"))
            if operation not in _ALLOWED_SAMPLE_INSERT_OPERATIONS:
                continue
            raw_items = normalized_data.get("items")
            normalized_items: list[dict[str, Any]] = []
            if isinstance(raw_items, list) and raw_items:
                for raw_item in raw_items:
                    if not isinstance(raw_item, dict):
                        continue
                    item = _normalize_sample_insert_item(dict(raw_item))
                    if str(item.get("library_path") or "").strip():
                        normalized_items.append(item)
            elif (
                str(normalized_data.get("library_path") or "").strip()
                or str(normalized_target.get("library_path") or "").strip()
            ):
                item = _normalize_sample_insert_item(normalized_data)
                if str(item.get("library_path") or "").strip():
                    normalized_items.append(item)
            if not normalized_items:
                continue
            normalized_data["operation"] = operation
            normalized_data["items"] = normalized_items
        elif action_type == "midi_compose":
            operation = _normalize_midi_compose_operation(normalized_data.get("operation"))
            if operation not in allowed_midi_operations:
                continue
            normalized_data["operation"] = operation
            if operation == "transpose_notes":
                semitones = _parse_action_float(normalized_data.get("semitones"))
                octaves = _parse_action_float(normalized_data.get("octaves"))
                if semitones is None and octaves is None:
                    continue
                if semitones is not None:
                    normalized_data["semitones"] = semitones
                if octaves is not None:
                    normalized_data["octaves"] = octaves
            elif operation == "convert_audio_to_midi":
                pass
            elif operation == "chop_notes":
                subdivision = _parse_action_int(
                    normalized_data.get("subdivision")
                    or normalized_data.get("subdivision_divisor")
                )
                if subdivision is not None and subdivision > 0:
                    normalized_data["subdivision"] = subdivision
            else:
                normalized_notes = _normalize_midi_notes_payload(
                    normalized_data.get("notes")
                )
                if normalized_notes:
                    normalized_data["notes"] = normalized_notes
                progression = normalized_data.get("progression")
                has_progression = (
                    isinstance(progression, list) and len(progression) > 0
                ) or (
                    isinstance(progression, str) and progression.strip()
                )
                if not normalized_notes and not has_progression:
                    continue
        elif action_type == "stem_separate":
            operation = re.sub(
                r"[^a-z0-9]+", "_",
                str(normalized_data.get("operation") or "").strip().lower(),
            ).strip("_")
            if operation not in _ALLOWED_STEM_SEPARATE_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "role_override":
            operation = _normalize_role_override_operation(normalized_data.get("operation") or "set")
            if operation not in _ALLOWED_ROLE_OVERRIDE_OPERATIONS:
                continue
            normalized_data["operation"] = operation
        elif action_type == "audio_enhance":
            operation = re.sub(
                r"[^a-z0-9]+", "_",
                str(normalized_data.get("operation") or "").strip().lower(),
            ).strip("_")
            if operation in {"phone_cleanup", "phone_mic", "cleanup", "denoise"}:
                operation = "phone_mic_cleanup"
            if operation != "phone_mic_cleanup":
                continue
            normalized_data["operation"] = operation

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
        normalized_goal["type"] = _normalize_mix_goal_type(
            normalized_goal.get("type")
        )
        normalized_goal["execution_profile"] = _normalize_mix_execution_profile(
            normalized_goal.get("execution_profile")
        )
        normalized_goal["audibility"] = _normalize_mix_audibility(
            normalized_goal.get("audibility")
        )
        normalized_reference_target = _normalize_mix_reference_target(
            normalized_goal.get("reference_target")
        )
        if normalized_reference_target is not None:
            normalized_goal["reference_target"] = normalized_reference_target
            normalized_goal["reference_mode"] = _normalize_mix_reference_mode(
                normalized_goal.get("reference_mode")
            )
            normalized_goal["reference_closeness"] = (
                _normalize_mix_reference_closeness(
                    normalized_goal.get("reference_closeness")
                )
            )
        else:
            normalized_goal.pop("reference_target", None)
            normalized_goal.pop("reference_mode", None)
            normalized_goal.pop("reference_closeness", None)
        normalized_goal["style_tags"] = _normalize_mix_style_tags(
            normalized_goal.get("style_tags")
        )
        normalized_goal["destructive_ok"] = normalized_goal.get("destructive_ok") is True
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
    client_capabilities: set[str],
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
            client_capabilities=client_capabilities,
        )
        if not normalized["actions"]:
            return None, ["daw_assistant_actions had no valid actions."]
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


def _daw_actions_success_payload(
    *,
    payload: Dict[str, Any],
    assistant_message: str,
    actions: list[dict[str, Any]],
) -> Dict[str, Any]:
    return {
        "id": payload.get("id"),
        "model": payload.get("model"),
        "output": [
            {
                "type": "function_call",
                "name": "daw_assistant_actions",
                "arguments": {
                    "assistant_message": assistant_message,
                    "actions": actions,
                },
            }
        ],
        "usage": payload.get("usage") if isinstance(payload.get("usage"), dict) else {},
    }


def _is_korean_text(text: str) -> bool:
    return bool(re.search(r"[\uac00-\ud7af]", str(text or "")))


def _is_capability_question(user_text: str) -> bool:
    text = str(user_text or "").strip().lower()
    if not text:
        return False
    if re.search(
        r"\b(what can you do|what do you do|help me use|how can you help|"
        r"available commands|capabilities|what are you able to do)\b",
        text,
    ):
        return True
    return bool(re.search(r"(무슨|뭐|어떤).{0,8}(작업|기능|할 수|해줄)", text))


def _capability_message(user_text: str) -> str:
    if _is_korean_text(user_text):
        return (
            "오디오 편집, 보컬 분리, 피치/키 변경, MIDI 클립 만들기, 샘플 배치, "
            "트랙 정리, 이펙트/자동화 편집을 도와줄 수 있어요. 원하는 작업을 바로 말해 주세요."
        )
    return (
        "I can edit clips, split vocals, change pitch/key, create MIDI clips, "
        "place samples, organize tracks, and adjust effects or automation. Tell me the edit you want."
    )


def _is_basic_midi_creation_request(user_text: str) -> bool:
    text = str(user_text or "").strip().lower()
    if not text:
        return False
    if re.search(r"(미디|midi).{0,12}(찍|만들|생성|클립)", text):
        return True
    if re.search(r"(음정|멜로디|코드).{0,12}(찍|만들|생성)", text):
        return True
    return bool(
        re.search(
            r"\b(create|make|write|add|compose)\b.{0,24}\b(midi|piano|melody|chord)\b",
            text,
        )
    )


def _simple_midi_clip_action() -> dict[str, Any]:
    return {
        "type": "midi_compose",
        "data": {
            "operation": "create_clip",
            "instrument_name": "Piano",
            "label": "AI MIDI",
            "length_measures": 4,
            "notes": [
                {"pitch": 60, "start_beat": 0, "length_beats": 1, "velocity": 0.78},
                {"pitch": 64, "start_beat": 1, "length_beats": 1, "velocity": 0.74},
                {"pitch": 67, "start_beat": 2, "length_beats": 1, "velocity": 0.76},
                {"pitch": 72, "start_beat": 3, "length_beats": 1, "velocity": 0.74},
                {"pitch": 69, "start_beat": 4, "length_beats": 1, "velocity": 0.76},
                {"pitch": 67, "start_beat": 5, "length_beats": 1, "velocity": 0.74},
                {"pitch": 64, "start_beat": 6, "length_beats": 1, "velocity": 0.74},
                {"pitch": 60, "start_beat": 7, "length_beats": 1, "velocity": 0.78},
                {"pitch": 60, "start_beat": 8, "length_beats": 2, "velocity": 0.70},
                {"pitch": 65, "start_beat": 10, "length_beats": 2, "velocity": 0.72},
                {"pitch": 67, "start_beat": 12, "length_beats": 2, "velocity": 0.74},
                {"pitch": 72, "start_beat": 14, "length_beats": 2, "velocity": 0.76},
            ],
            "target": {"prefer_selected": False},
        },
    }


def _sample_insert_roles_from_user_text(user_text: str) -> list[str]:
    text = str(user_text or "").strip().lower()
    if not text:
        return []

    if re.search(
        r"\b(do\s*not|don't|dont|without|no)\b.{0,32}\b("
        r"add|insert|place|put|create|make|drop|lay)\b.{0,32}\b("
        r"clip|clips|sample|samples|audio|track|tracks|row|rows|material)\b",
        text,
    ):
        return []

    explicit_insert_intent = bool(
        re.search(r"\b(add|insert|place|put|drop|lay)\b", text)
    )
    creation_intent = bool(
        re.search(
            r"\b(make|create|build)\b.{0,32}\b("
            r"beat|beats|drum|drums|groove|grooves|loop|loops|pattern|patterns|"
            r"kick|kicks|snare|snares|clap|claps|hat|hats|hihat|hihats|perc|"
            r"percussion|cymbal|cymbals|tom|toms)\b",
            text,
        )
    )
    request_intent = bool(
        re.search(
            r"\b(give|need|want)\b.{0,32}\b("
            r"some|a|an|new|more|beat|beats|drum|drums|groove|grooves|loop|"
            r"loops|pattern|patterns|kick|kicks|snare|snares|clap|claps|"
            r"hat|hats|hihat|hihats|perc|percussion|cymbal|cymbals|tom|toms)\b",
            text,
        )
    )
    if not (explicit_insert_intent or creation_intent or request_intent):
        return []

    has_level_or_existing_edit_intent = bool(
        re.search(
            r"\b(louder|quieter|softer|harder|punchier|volume|gain|fader|"
            r"level|levels|db|turn\s+up|turn\s+down|bring\s+up|bring\s+down|"
            r"raise|lower|boost|reduce|attenuate|mute|unmute|solo|pan)\b",
            text,
        )
    )
    has_stable_insert_verb = bool(re.search(r"\b(add|insert|place|put|lay)\b", text))
    references_existing_material = bool(
        re.search(
            r"\b(track|tracks|row|rows|selected|current|existing|already)\b",
            text,
        )
        or re.search(
            r"\b(the|this|that)\s+(kick|kicks|snare|snares|clap|claps|"
            r"hat|hats|hihat|hihats|drum|drums|beat|loop|bass\s*drum)\b",
            text,
        )
    )
    if has_level_or_existing_edit_intent and (
        references_existing_material or not has_stable_insert_verb
    ):
        return []

    roles: list[str] = []
    role_patterns = (
        ("kick", r"\b(kick|kicks|bd|bass\s*drum)\b"),
        ("snare", r"\b(snare|snares)\b"),
        ("clap", r"\b(clap|claps)\b"),
        ("hat", r"\b(hi[-\s]?hat|hi[-\s]?hats|hihat|hihats|hat|hats)\b"),
        ("perc", r"\b(perc|percussion|shaker|shakers|rim|rimshot)\b"),
        ("cymbal", r"\b(cymbal|cymbals|crash|ride|open\s*hat|open\s*hats)\b"),
        ("tom", r"\b(tom|toms)\b"),
    )
    for role, pattern in role_patterns:
        if re.search(pattern, text) and role not in roles:
            roles.append(role)

    if not roles and re.search(r"\b(drum|drums|beat|groove|loop)\b", text):
        roles = ["kick", "snare", "hat"]

    return roles


def _sample_insert_action_for_roles(roles: list[str]) -> dict[str, Any]:
    row_by_role = {
        "kick": 0,
        "snare": 1,
        "clap": 1,
        "hat": 2,
        "perc": 3,
        "cymbal": 4,
        "tom": 5,
    }
    step_by_role = {
        "kick": 2.0,
        "snare": 4.0,
        "clap": 4.0,
        "hat": 0.5,
        "perc": 1.0,
        "cymbal": 4.0,
        "tom": 2.0,
    }
    offset_by_role = {
        "kick": 0.0,
        "snare": 2.0,
        "clap": 2.0,
        "hat": 0.0,
        "perc": 0.0,
        "cymbal": 0.0,
        "tom": 1.0,
    }
    items: list[dict[str, Any]] = []
    for role in roles:
        item: dict[str, Any] = {
            "library_path": f"role:{role}",
            "row_index": row_by_role.get(role, 0),
            "start_beat": offset_by_role.get(role, 0.0),
            "length_measures": 4,
            "step_beats": step_by_role.get(role, 1.0),
            "target": {
                "prefer_selected": False,
                "row_index": row_by_role.get(role, 0),
            },
        }
        items.append(item)
    return {
        "type": "sample_insert",
        "data": {
            "operation": "insert_audio_clips",
            "items": items,
            "target": {"prefer_selected": False},
        },
    }


def _is_glue_or_combine_request(user_text: str) -> bool:
    text = str(user_text or "").strip().lower()
    if not text:
        return False
    return bool(
        re.search(
            r"\b(combine|merge|glue|consolidate|bounce|render)\b.{0,40}\b("
            r"clip|clips|sample|samples|audio|drum|drums|track|tracks)\b",
            text,
        )
        or re.search(r"(합치|병합|붙여|묶어).{0,12}(클립|샘플|드럼|오디오)", text)
    )


def _request_selection_has_multiple_clips(request_body: Dict[str, Any]) -> bool:
    messages = request_body.get("messages")
    if not isinstance(messages, list):
        return False
    for message in messages:
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, str) or "SELECTION_SNAPSHOT" not in content:
            continue
        match = re.search(r"selected_clip_indices\s*=\s*([0-9,\s]+)", content)
        if not match:
            continue
        indices = [
            token.strip()
            for token in match.group(1).split(",")
            if token.strip().isdigit()
        ]
        if len(indices) >= 2:
            return True
    return False


def _fallback_structured_payload_for_user_text(
    *,
    request_body: Dict[str, Any],
    payload: Dict[str, Any],
    user_text: str,
    client_capabilities: set[str],
) -> Dict[str, Any] | None:
    if _is_capability_question(user_text):
        return _informational_success_payload(
            payload=payload,
            message=_capability_message(user_text),
        )

    if _is_basic_midi_creation_request(user_text):
        if "daw.midi_compose.instrument_insert" not in client_capabilities:
            message = (
                "이 버전에서는 새 MIDI 악기 클립 생성이 지원되지 않아요. 기존 MIDI 클립이나 악기를 선택해 주세요."
                if _is_korean_text(user_text)
                else "This app version needs an existing MIDI clip or instrument selected for MIDI edits."
            )
            return _informational_success_payload(payload=payload, message=message)
        return _daw_actions_success_payload(
            payload=payload,
            assistant_message=(
                "간단한 피아노 MIDI 클립을 만들게요."
                if _is_korean_text(user_text)
                else "I’ll create a simple piano MIDI clip."
            ),
            actions=[_simple_midi_clip_action()],
        )

    sample_roles = _sample_insert_roles_from_user_text(user_text)
    if sample_roles:
        if "daw.sample_insert.library" not in client_capabilities:
            return None
        return _daw_actions_success_payload(
            payload=payload,
            assistant_message=(
                "드럼 샘플을 오디오 트랙에 배치할게요."
                if _is_korean_text(user_text)
                else "I’ll place those drum samples on audio rows."
            ),
            actions=[_sample_insert_action_for_roles(sample_roles)],
        )

    if _is_glue_or_combine_request(user_text):
        if _request_selection_has_multiple_clips(request_body):
            return _daw_actions_success_payload(
                payload=payload,
                assistant_message=(
                    "선택한 클립들을 하나로 합칠게요."
                    if _is_korean_text(user_text)
                    else "I’ll combine the selected clips into one clip."
                ),
                actions=[
                    {
                        "type": "clip_edit",
                        "data": {
                            "operation": "glue",
                            "target": {"scope": "selected"},
                        },
                    }
                ],
            )
        return _daw_actions_success_payload(
            payload=payload,
            assistant_message=(
                "합칠 클립을 먼저 확인할게요."
                if _is_korean_text(user_text)
                else "I need to know which clips to combine."
            ),
            actions=[
                {
                    "type": "clarify",
                    "data": {
                        "question": (
                            "어떤 클립을 합칠까요?"
                            if _is_korean_text(user_text)
                            else "Which clips should I combine?"
                        ),
                        "options": (
                            ["선택한 클립", "드럼 클립"]
                            if _is_korean_text(user_text)
                            else ["Selected clips", "Drum clips"]
                        ),
                    },
                }
            ],
        )

    return None


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
        "mix_model_request missing actions array.",
        "mix_model_request had no valid actions.",
        "daw_assistant_actions missing actions array.",
        "daw_assistant_actions had no valid actions.",
    } or normalized.endswith("arguments are not a json object.")


def _normalize_success_payload(
    *,
    request_body: Dict[str, Any],
    payload: Dict[str, Any],
    client_capabilities: set[str],
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
        if item_type in {"reasoning", "reasoning_summary"}:
            continue
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
            client_capabilities=client_capabilities,
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
        if normalized_output:
            normalized_payload = dict(payload)
            normalized_payload["output"] = normalized_output
            return normalized_payload, issues, False
        if issues:
            structured_fallback = _fallback_structured_payload_for_user_text(
                request_body=request_body,
                payload=payload,
                user_text=user_text,
                client_capabilities=client_capabilities,
            )
            if structured_fallback is not None:
                return structured_fallback, issues, False
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
        structured_fallback = _fallback_structured_payload_for_user_text(
            request_body=request_body,
            payload=payload,
            user_text=user_text,
            client_capabilities=client_capabilities,
        )
        if structured_fallback is not None:
            return structured_fallback, issues, False
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
    prompt_limits = get_prompt_limits(
        subscription_tier,
        user_context.get("limit_overrides"),
    )

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

    is_v3_request = _is_v3_responses_path(request_path)
    if is_v3_request and not _v3_enabled():
        return _finalize(
            json_response(
                503,
                {
                    "error": {
                        "code": "v3_disabled",
                        "message": "AI V3 is temporarily disabled.",
                    }
                },
            ),
            error="v3_disabled",
        )
    if is_v3_request:
        try:
            _validate_v3_request_body(body)
        except ValueError as error:
            return _finalize(
                json_response(400, {"error": str(error)}),
                error="invalid_v3_request",
            )

    if http_method == "POST" and request_path.endswith("/v1/llm/conversation-events"):
        try:
            return _finalize(_handle_conversation_event(body=body, user_id=user_id))
        except Exception as error:
            capture_exception(
                error,
                context=request_log_context,
                tags={"service": "llm_proxy"},
            )
            return _finalize(
                json_response(500, {"error": "Conversation event could not be recorded."}),
                error="conversation_event_failed",
            )

    prompt_trace_id = _prompt_trace_id_from_body(body)
    request_log_context["prompt_trace_id"] = prompt_trace_id
    project_id = str(body.get("project_id") or "").strip()
    request_log_context["project_id"] = project_id
    analytics_enabled = analytics_enabled_from_body(body)
    client_context = client_context_from_body(body)
    client_capabilities = _client_capabilities_from_context(client_context)
    raw_ai_feature = (
        "ai_chat_v3"
        if is_v3_request
        else str(body.get("ai_feature") or "ai_chat").strip() or "ai_chat"
    )
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

    configured_model = (
        _configured_v3_model() if is_v3_request else _configured_model()
    )
    default_model = configured_model or DEFAULT_MODEL
    runtime_config = get_ai_feature_runtime(ai_feature, fallback_model=default_model)
    is_structured_request = any(key in body for key in _STRUCTURED_MIXROOM_FIELDS)
    conversation_state_mode_requested = _conversation_state_mode_from_body(body)
    conversation_session_id = str(body.get("conversation_session_id") or "").strip()
    conversation_state_mode_effective = conversation_state_mode_requested
    if _uses_openai_conversation_state(conversation_state_mode_effective):
        if (
            provider.name != DEFAULT_PROVIDER
            or not conversation_session_id
            or _conversation_state_table_client() is None
        ):
            conversation_state_mode_effective = "manual_history"

    normalized_body = dict(body)
    normalized_body["conversation_state_mode"] = conversation_state_mode_effective

    try:
        request_body = _normalize_request_body(
            normalized_body,
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
    if is_v3_request:
        request_body["model"] = configured_model or "gpt-5.6-luna"
        request_body["reasoning"] = {
            "effort": _configured_v3_reasoning_effort(),
        }
        request_body["max_output_tokens"] = min(
            int(request_body.get("max_output_tokens") or 4096),
            4096,
        )
        request_body["parallel_tool_calls"] = False
        # The configured V3 Luna model requires the extended cache setting.
        request_body["prompt_cache_retention"] = "24h"
        # V3 is intentionally retained in OpenAI Responses for production
        # diagnostics; the proxy owns and enforces this policy.
        request_body["store"] = True

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
    request_log_context["conversation_state_mode_requested"] = (
        conversation_state_mode_requested
    )
    request_log_context["conversation_state_mode_effective"] = (
        conversation_state_mode_effective
    )
    if conversation_session_id:
        request_log_context["conversation_session_id_hash"] = _short_hash(
            conversation_session_id
        )

    provider_roundtrip_ms = 0
    openai_api_ms = 0
    response_normalize_ms = 0
    provider_response_id = ""
    openai_conversation_id = ""
    openai_conversation_created = False
    openai_conversation_tool_outputs_appended = 0

    def _observability_payload() -> dict[str, Any]:
        return _compact_dict(
            {
                "prompt_trace_id": prompt_trace_id,
                "request_id": request_log_context.get("request_id"),
                "provider": provider.name,
                "effective_model": str(request_body.get("model") or "").strip(),
                "provider_response_id": provider_response_id,
                "runtime_config_fingerprint": runtime_config_fingerprint,
                "conversation_state_mode_requested": conversation_state_mode_requested,
                "conversation_state_mode_effective": conversation_state_mode_effective,
                "conversation_session_id_hash": (
                    _short_hash(conversation_session_id)
                    if conversation_session_id
                    else ""
                ),
                "openai_conversation_id_hash": (
                    _short_hash(openai_conversation_id)
                    if openai_conversation_id
                    else ""
                ),
                "openai_conversation_created": (
                    True if openai_conversation_created else None
                ),
                "openai_conversation_tool_outputs_appended": (
                    openai_conversation_tool_outputs_appended or None
                ),
                "openai_conversation_id": (
                    openai_conversation_id
                    if os.environ.get("LLM_EXPOSE_OPENAI_CONVERSATION_IDS", "false")
                    .strip()
                    .lower()
                    == "true"
                    else ""
                ),
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

    if _uses_openai_conversation_state(conversation_state_mode_effective):
        try:
            openai_conversation_id, openai_conversation_created = (
                _ensure_openai_conversation_id(
                    api_key=api_key,
                    user_id=user_id,
                    project_id=project_id,
                    ai_feature=ai_feature,
                    conversation_state_mode=conversation_state_mode_effective,
                    conversation_session_id=conversation_session_id,
                    runtime_config_fingerprint=runtime_config_fingerprint,
                    request_body=request_body,
                )
            )
            if openai_conversation_id:
                request_body["conversation"] = openai_conversation_id
                request_log_context["openai_conversation_id_hash"] = _short_hash(
                    openai_conversation_id
                )
        except Exception as error:
            capture_exception(
                error,
                context={
                    **request_log_context,
                    "conversation_state_mode_requested": conversation_state_mode_requested,
                },
                tags={"service": "llm_proxy"},
            )
            conversation_state_mode_effective = "manual_history"
            normalized_body = dict(body)
            normalized_body["conversation_state_mode"] = "manual_history"
            request_body = _normalize_request_body(
                normalized_body,
                default_model=str(runtime_config.get("model") or default_model),
                ai_feature=ai_feature,
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
            _update_request_log_context_with_cache_request(
                request_log_context,
                request_body,
            )
            runtime_config_fingerprint = _runtime_config_fingerprint(
                ai_feature=ai_feature,
                provider_name=provider.name,
                request_body=request_body,
                runtime_config=runtime_config,
            )
            request_log_context["effective_model"] = str(
                request_body.get("model") or ""
            ).strip()
            request_log_context["runtime_config_fingerprint"] = (
                runtime_config_fingerprint
            )
            request_log_context["conversation_state_mode_effective"] = (
                conversation_state_mode_effective
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
                "conversation_state_mode_requested": conversation_state_mode_requested,
                "conversation_state_mode_effective": conversation_state_mode_effective,
                "conversation_session_id_hash": (
                    _short_hash(conversation_session_id)
                    if conversation_session_id
                    else ""
                ),
                "openai_conversation_id_hash": (
                    _short_hash(openai_conversation_id)
                    if openai_conversation_id
                    else ""
                ),
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
            openai_conversation_tool_outputs_appended = int(
                provider_observability.get(
                    "openai_conversation_tool_outputs_appended"
                )
                or 0
            )
            if provider_roundtrip_ms > 0:
                request_log_context["provider_roundtrip_ms"] = provider_roundtrip_ms
            if openai_api_ms > 0:
                request_log_context["openai_api_ms"] = openai_api_ms
            if openai_conversation_tool_outputs_appended > 0:
                request_log_context["openai_conversation_tool_outputs_appended"] = (
                    openai_conversation_tool_outputs_appended
                )
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
            client_capabilities=client_capabilities,
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
    client_status_code = _client_status_code_for_upstream_error(status_code)
    if client_status_code != status_code:
        response_payload["error"] = "LLM upstream rate limited. Please try again shortly."
        response_payload["code"] = "llm_upstream_rate_limited"
    proxy_response = {
        **proxy_response,
        "statusCode": client_status_code,
        "body": json.dumps(response_payload),
    }
    return _finalize(proxy_response, error=error_code)
