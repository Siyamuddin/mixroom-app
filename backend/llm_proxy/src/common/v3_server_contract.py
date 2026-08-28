from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Mapping, Sequence


REQUEST_CONTRACT = "mixroom_v3_context_v1"
RESPONSE_SCHEMA_VERSION = "v3_plan_response_server_v1"
CONTRACT_VERSION = "mixroom_v3_server_contract_2"

_ASSET_DIRECTORY = Path(__file__).with_name("v3_contract_assets")
_METADATA = json.loads(
    (_ASSET_DIRECTORY / "v3_contract_metadata.json").read_text(encoding="utf-8")
)
PLAN_SCHEMA_VERSION = str(_METADATA["plan_schema_version"])
SERVER_COMMAND_TYPES = frozenset(str(value) for value in _METADATA["command_types"])
RESOURCE_REF_COMMAND_TYPES = frozenset(
    str(value) for value in _METADATA["resource_ref_command_types"]
)

_INSTRUCTIONS = (_ASSET_DIRECTORY / "v3_instructions.txt").read_text(
    encoding="utf-8"
).strip()
_RESOURCE_REF_INSTRUCTIONS = (
    _ASSET_DIRECTORY / "v3_instructions_resource_refs.txt"
).read_text(encoding="utf-8").strip()
_ALIGN_TEMPO_RETRY_INSTRUCTIONS = (
    _ASSET_DIRECTORY / "v3_align_tempo_retry_instructions.txt"
).read_text(encoding="utf-8").strip()
_TOOLS = {
    False: json.loads(
        (_ASSET_DIRECTORY / "v3_submit_plan_tool.json").read_text(encoding="utf-8")
    ),
    True: json.loads(
        (_ASSET_DIRECTORY / "v3_submit_plan_tool_resource_refs.json").read_text(
            encoding="utf-8"
        )
    ),
}

_REQUIRED_REQUEST_FIELDS = frozenset(
    {
        "request_contract",
        "original_request",
        "conversation",
        "core_context",
        "plan_schema_version",
        "supported_command_types",
        "resource_refs_enabled",
    }
)
_OPTIONAL_REQUEST_FIELDS = frozenset(
    {"project_id", "prompt_trace_id", "analytics_context"}
)
_ALLOWED_REQUEST_FIELDS = _REQUIRED_REQUEST_FIELDS | _OPTIONAL_REQUEST_FIELDS
_PROHIBITED_AI_FIELDS = frozenset(
    {
        "instructions",
        "prompt",
        "system_prompt",
        "developer_prompt",
        "tools",
        "tool_choice",
        "parallel_tool_calls",
        "model",
        "provider",
        "reasoning",
        "temperature",
        "max_output_tokens",
        "max_tokens",
        "prompt_cache_key",
        "prompt_cache_retention",
        "cache",
        "store",
        "input",
        "messages",
        "request_overrides",
    }
)
_ALLOWED_ANALYTICS_FIELDS = frozenset(
    {"app_version", "platform", "ai_architecture", "subscription_plan"}
)

MAX_REQUEST_BYTES = 180_000
MAX_ORIGINAL_REQUEST_CHARS = 8_000
MAX_CONVERSATION_TURNS = 12
MAX_CONVERSATION_TURN_CHARS = 8_000
MAX_CONVERSATION_CHARS = 32_000
MAX_CORE_CONTEXT_BYTES = 140_000
MAX_CONTEXT_DEPTH = 12
MAX_CONTEXT_NODES = 10_000
MAX_COLLECTION_ITEMS = 512
MAX_CONTEXT_STRING_CHARS = 32_000
MAX_CONTEXT_TOTAL_STRING_CHARS = 120_000
MAX_SUPPORTED_COMMAND_TYPES = 64
MAX_IDENTIFIER_CHARS = 128
MAX_TRACE_ID_CHARS = 64


class V3ContractError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def _contract_error(code: str, message: str) -> V3ContractError:
    return V3ContractError(code, message)


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _bounded_string(value: Any, *, field: str, maximum: int, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise _contract_error("invalid_v3_context_request", f"'{field}' must be a string.")
    normalized = value.strip()
    if not allow_empty and not normalized:
        raise _contract_error("invalid_v3_context_request", f"'{field}' must not be empty.")
    if len(value) > maximum:
        raise _contract_error("v3_context_request_limit", f"'{field}' exceeds its size limit.")
    return normalized


def _validate_context_value(value: Any) -> None:
    state = {"nodes": 0, "string_chars": 0}

    def visit(current: Any, depth: int) -> None:
        state["nodes"] += 1
        if state["nodes"] > MAX_CONTEXT_NODES or depth > MAX_CONTEXT_DEPTH:
            raise _contract_error("v3_context_request_limit", "'core_context' is too complex.")
        if current is None or isinstance(current, bool):
            return
        if isinstance(current, (int, float)) and not isinstance(current, bool):
            if isinstance(current, float) and not math.isfinite(current):
                raise _contract_error("invalid_v3_context_request", "'core_context' contains a non-finite number.")
            return
        if isinstance(current, str):
            if len(current) > MAX_CONTEXT_STRING_CHARS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized string.")
            state["string_chars"] += len(current)
            if state["string_chars"] > MAX_CONTEXT_TOTAL_STRING_CHARS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains too much text.")
            return
        if isinstance(current, list):
            if len(current) > MAX_COLLECTION_ITEMS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized list.")
            for item in current:
                visit(item, depth + 1)
            return
        if isinstance(current, dict):
            if len(current) > MAX_COLLECTION_ITEMS:
                raise _contract_error("v3_context_request_limit", "'core_context' contains an oversized object.")
            for key, item in current.items():
                if not isinstance(key, str) or not key or len(key) > MAX_IDENTIFIER_CHARS:
                    raise _contract_error("invalid_v3_context_request", "'core_context' contains an invalid key.")
                visit(item, depth + 1)
            return
        raise _contract_error("invalid_v3_context_request", "'core_context' contains an unsupported value.")

    visit(value, 0)


def _validate_conversation(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        raise _contract_error("invalid_v3_context_request", "'conversation' must be a list.")
    if len(value) > MAX_CONVERSATION_TURNS:
        raise _contract_error("v3_context_request_limit", "'conversation' has too many turns.")
    result: list[dict[str, str]] = []
    total_chars = 0
    for item in value:
        if not isinstance(item, dict) or set(item) != {"role", "content"}:
            raise _contract_error("invalid_v3_context_request", "Each conversation turn must contain only role and content.")
        role = str(item.get("role") or "").strip()
        if role not in {"user", "assistant"}:
            raise _contract_error("invalid_v3_context_request", "Conversation roles must be user or assistant.")
        content = _bounded_string(
            item.get("content"),
            field="conversation.content",
            maximum=MAX_CONVERSATION_TURN_CHARS,
        )
        total_chars += len(content)
        if total_chars > MAX_CONVERSATION_CHARS:
            raise _contract_error("v3_context_request_limit", "'conversation' exceeds its text limit.")
        result.append({"role": role, "content": content})
    return result


def validate_context_request(body: Mapping[str, Any], *, raw_body_bytes: int) -> dict[str, Any]:
    if raw_body_bytes > MAX_REQUEST_BYTES:
        raise _contract_error("v3_context_request_limit", "V3 context request is too large.")
    actual_fields = set(body)
    prohibited = actual_fields & _PROHIBITED_AI_FIELDS
    if prohibited:
        raise _contract_error(
            "v3_client_ai_configuration_forbidden",
            "Client-provided AI configuration is not allowed for this request contract.",
        )
    unknown = actual_fields - _ALLOWED_REQUEST_FIELDS
    if unknown:
        raise _contract_error("v3_context_unknown_fields", "V3 context request contains unknown fields.")
    missing = _REQUIRED_REQUEST_FIELDS - actual_fields
    if missing:
        raise _contract_error("v3_context_missing_fields", "V3 context request is missing required fields.")
    if body.get("request_contract") != REQUEST_CONTRACT:
        raise _contract_error("v3_request_contract_unsupported", "Unsupported V3 request contract.")
    if body.get("plan_schema_version") != PLAN_SCHEMA_VERSION:
        raise _contract_error("v3_plan_schema_unsupported", "Unsupported V3 plan schema version.")

    original_request = _bounded_string(
        body.get("original_request"),
        field="original_request",
        maximum=MAX_ORIGINAL_REQUEST_CHARS,
    )
    conversation = _validate_conversation(body.get("conversation"))
    core_context = body.get("core_context")
    if not isinstance(core_context, dict):
        raise _contract_error("invalid_v3_context_request", "'core_context' must be an object.")
    _validate_context_value(core_context)
    if len(_canonical_json(core_context).encode("utf-8")) > MAX_CORE_CONTEXT_BYTES:
        raise _contract_error("v3_context_request_limit", "'core_context' exceeds its size limit.")

    raw_command_types = body.get("supported_command_types")
    if not isinstance(raw_command_types, list) or not raw_command_types:
        raise _contract_error("invalid_v3_context_request", "'supported_command_types' must be a non-empty list.")
    if len(raw_command_types) > MAX_SUPPORTED_COMMAND_TYPES:
        raise _contract_error("v3_context_request_limit", "Too many supported command types were supplied.")
    if any(not isinstance(value, str) or not value.strip() for value in raw_command_types):
        raise _contract_error("invalid_v3_context_request", "Supported command types must be non-empty strings.")
    declared_types = {value.strip() for value in raw_command_types}
    effective_types = frozenset(declared_types & SERVER_COMMAND_TYPES)
    if not effective_types:
        raise _contract_error("v3_command_surface_empty", "No mutually supported V3 commands were supplied.")

    resource_refs_enabled = body.get("resource_refs_enabled")
    if not isinstance(resource_refs_enabled, bool):
        raise _contract_error("invalid_v3_context_request", "'resource_refs_enabled' must be a boolean.")

    analytics_context = body.get("analytics_context", {})
    if not isinstance(analytics_context, dict) or set(analytics_context) - _ALLOWED_ANALYTICS_FIELDS:
        raise _contract_error("invalid_v3_context_request", "'analytics_context' contains unsupported fields.")
    normalized_analytics: dict[str, str] = {}
    for key, value in analytics_context.items():
        normalized_analytics[key] = _bounded_string(
            value,
            field=f"analytics_context.{key}",
            maximum=128,
            allow_empty=True,
        )

    project_id = _bounded_string(
        body.get("project_id", ""), field="project_id", maximum=MAX_IDENTIFIER_CHARS, allow_empty=True
    )
    prompt_trace_id = _bounded_string(
        body.get("prompt_trace_id", ""), field="prompt_trace_id", maximum=MAX_TRACE_ID_CHARS, allow_empty=True
    )
    return {
        "original_request": original_request,
        "conversation": conversation,
        "core_context": copy.deepcopy(core_context),
        "supported_command_types": effective_types,
        "resource_refs_enabled": resource_refs_enabled,
        "project_id": project_id,
        "prompt_trace_id": prompt_trace_id,
        "analytics_context": normalized_analytics,
    }


def _command_type_for_variant(variant: Mapping[str, Any]) -> str:
    values = (
        variant.get("properties", {}).get("type", {}).get("enum", [])
        if isinstance(variant.get("properties"), dict)
        else []
    )
    return str(values[0]) if isinstance(values, list) and len(values) == 1 else ""


def build_submit_plan_tool(*, command_types: Sequence[str], resource_refs_enabled: bool) -> dict[str, Any]:
    effective_types = frozenset(command_types) & SERVER_COMMAND_TYPES
    if not effective_types:
        raise _contract_error("v3_command_surface_empty", "The effective V3 command surface is empty.")
    tool = copy.deepcopy(_TOOLS[resource_refs_enabled])
    command_items = tool["parameters"]["properties"]["commands"]["items"]
    command_items["anyOf"] = [
        variant
        for variant in command_items["anyOf"]
        if _command_type_for_variant(variant) in effective_types
    ]
    return tool


def build_provider_request(
    request: Mapping[str, Any],
    *,
    model: str,
    reasoning_effort: str,
    max_output_tokens: int = 8192,
    prompt_cache_retention: str = "24h",
    store: bool = True,
) -> dict[str, Any]:
    resource_refs_enabled = request["resource_refs_enabled"] is True
    tool = build_submit_plan_tool(
        command_types=request["supported_command_types"],
        resource_refs_enabled=resource_refs_enabled,
    )
    metadata = {
        "architecture": REQUEST_CONTRACT,
        "contract_version": CONTRACT_VERSION,
    }
    prompt_trace_id = str(request.get("prompt_trace_id") or "").strip()
    if prompt_trace_id:
        metadata["prompt_trace_id"] = prompt_trace_id[:MAX_TRACE_ID_CHARS]
    return {
        "model": model.strip(),
        "instructions": _RESOURCE_REF_INSTRUCTIONS if resource_refs_enabled else _INSTRUCTIONS,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": f"ORIGINAL_REQUEST_VERBATIM:\n{request['original_request']}"},
                    {"type": "input_text", "text": f"RECENT_CONVERSATION_JSON:\n{_canonical_json(request['conversation'])}"},
                    {"type": "input_text", "text": f"CORE_CONTEXT_V3_JSON:\n{_canonical_json(request['core_context'])}"},
                ],
            }
        ],
        "tools": [tool],
        "tool_choice": {"type": "function", "name": "submit_plan_v3"},
        "parallel_tool_calls": False,
        "max_output_tokens": max(1, min(int(max_output_tokens), 8192)),
        "reasoning": {"effort": reasoning_effort},
        "prompt_cache_retention": prompt_cache_retention,
        "store": bool(store),
        "metadata": metadata,
    }


def build_align_tempo_retry_provider_request(
    request: Mapping[str, Any],
    *,
    model: str,
    reasoning_effort: str,
    max_output_tokens: int = 8192,
    prompt_cache_retention: str = "24h",
    store: bool = True,
) -> dict[str, Any]:
    provider_request = build_provider_request(
        request,
        model=model,
        reasoning_effort=reasoning_effort,
        max_output_tokens=max_output_tokens,
        prompt_cache_retention=prompt_cache_retention,
        store=store,
    )
    provider_request["instructions"] = "\n".join(
        [provider_request["instructions"], _ALIGN_TEMPO_RETRY_INSTRUCTIONS]
    )
    provider_request["metadata"] = {
        **provider_request["metadata"],
        "retry_reason": "production_goal_align_tempo_collapse",
    }
    return provider_request


def should_retry_align_tempo_collapse(plan: Mapping[str, Any]) -> bool:
    commands = plan.get("commands")
    return (
        plan.get("outcome") == "plan"
        and plan.get("goal_kind") == "production_goal"
        and isinstance(commands, list)
        and bool(commands)
        and all(
            isinstance(command, dict)
            and command.get("type") == "clip.align_tempo_to_project"
            for command in commands
        )
    )


def contract_fingerprint(*, command_types: Sequence[str], resource_refs_enabled: bool) -> str:
    policy = {
        "contract_version": CONTRACT_VERSION,
        "instructions": _RESOURCE_REF_INSTRUCTIONS if resource_refs_enabled else _INSTRUCTIONS,
        "tool": build_submit_plan_tool(
            command_types=command_types,
            resource_refs_enabled=resource_refs_enabled,
        ),
        "tool_choice": {"type": "function", "name": "submit_plan_v3"},
        "parallel_tool_calls": False,
    }
    return hashlib.sha256(_canonical_json(policy).encode("utf-8")).hexdigest()[:16]


def _matches_type(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "boolean": isinstance(value, bool),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def _validate_json_schema(value: Any, schema: Mapping[str, Any], path: str = "$", *, quiet: bool = False) -> None:
    def fail(message: str) -> None:
        raise _contract_error("v3_plan_schema_invalid", message if not quiet else "schema mismatch")

    any_of = schema.get("anyOf")
    if isinstance(any_of, list):
        matches = 0
        for candidate in any_of:
            try:
                _validate_json_schema(value, candidate, path, quiet=True)
                matches += 1
            except V3ContractError:
                pass
        if matches < 1:
            fail(f"{path} does not match an allowed schema.")
        return
    one_of = schema.get("oneOf")
    if isinstance(one_of, list):
        matches = 0
        for candidate in one_of:
            try:
                _validate_json_schema(value, candidate, path, quiet=True)
                matches += 1
            except V3ContractError:
                pass
        if matches != 1:
            fail(f"{path} does not match exactly one allowed schema.")
        return
    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not _matches_type(value, expected_type):
        fail(f"{path} has an invalid type.")
    if "const" in schema and value != schema["const"]:
        fail(f"{path} has an invalid value.")
    if isinstance(schema.get("enum"), list) and value not in schema["enum"]:
        fail(f"{path} has an invalid value.")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if any(key not in value for key in required):
            fail(f"{path} is missing a required field.")
        if schema.get("additionalProperties") is False and set(value) - set(properties):
            fail(f"{path} contains an unknown field.")
        for key, child in value.items():
            if key in properties:
                _validate_json_schema(child, properties[key], f"{path}.{key}", quiet=quiet)
    elif isinstance(value, list):
        if isinstance(schema.get("minItems"), int) and len(value) < schema["minItems"]:
            fail(f"{path} has too few items.")
        if isinstance(schema.get("maxItems"), int) and len(value) > schema["maxItems"]:
            fail(f"{path} has too many items.")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child in enumerate(value):
                _validate_json_schema(child, item_schema, f"{path}[{index}]", quiet=quiet)
    elif isinstance(value, str):
        if isinstance(schema.get("minLength"), int) and len(value) < schema["minLength"]:
            fail(f"{path} is too short.")
        if isinstance(schema.get("maxLength"), int) and len(value) > schema["maxLength"]:
            fail(f"{path} is too long.")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            fail(f"{path} is below its minimum.")
        if "maximum" in schema and value > schema["maximum"]:
            fail(f"{path} is above its maximum.")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            fail(f"{path} is below its exclusive minimum.")


def parse_and_validate_provider_plan(
    payload: Mapping[str, Any],
    *,
    command_types: Sequence[str],
    resource_refs_enabled: bool,
) -> dict[str, Any]:
    output = payload.get("output")
    if not isinstance(output, list):
        raise _contract_error("v3_provider_output_invalid", "Provider output is missing.")
    calls = [item for item in output if isinstance(item, dict) and item.get("type") == "function_call"]
    if len(calls) != 1 or calls[0].get("name") != "submit_plan_v3":
        raise _contract_error("v3_provider_output_invalid", "Provider tool call is invalid.")
    raw_arguments = calls[0].get("arguments")
    if isinstance(raw_arguments, str):
        try:
            plan = json.loads(raw_arguments)
        except json.JSONDecodeError as error:
            raise _contract_error("v3_provider_output_invalid", "Provider arguments are invalid JSON.") from error
    elif isinstance(raw_arguments, dict):
        plan = copy.deepcopy(raw_arguments)
    else:
        raise _contract_error("v3_provider_output_invalid", "Provider arguments are invalid.")
    if not isinstance(plan, dict):
        raise _contract_error("v3_provider_output_invalid", "Provider plan must be an object.")
    tool = build_submit_plan_tool(
        command_types=command_types,
        resource_refs_enabled=resource_refs_enabled,
    )
    _validate_json_schema(plan, tool["parameters"])
    effective_types = frozenset(command_types) & SERVER_COMMAND_TYPES
    for command in plan.get("commands", []):
        if not isinstance(command, dict) or command.get("type") not in effective_types:
            raise _contract_error("v3_command_outside_surface", "Provider command is outside the effective surface.")
    commands = plan.get("commands", [])
    outcome = plan.get("outcome")
    if bool(commands) != (outcome == "plan"):
        raise _contract_error("v3_plan_outcome_invalid", "Provider plan outcome does not match its commands.")
    return plan


def response_envelope(
    *,
    plan: Mapping[str, Any],
    prompt_trace_id: str,
    request_id: str,
    fingerprint: str,
) -> dict[str, Any]:
    trace = {
        "contract_version": CONTRACT_VERSION,
        "contract_fingerprint": fingerprint,
    }
    if prompt_trace_id:
        trace["prompt_trace_id"] = prompt_trace_id
    if request_id:
        trace["request_id"] = request_id
    return {
        "schema_version": RESPONSE_SCHEMA_VERSION,
        "plan": copy.deepcopy(dict(plan)),
        "trace": trace,
    }
