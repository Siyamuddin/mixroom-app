from __future__ import annotations

import json
import os
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Tuple

from common.llm_contract import (
    DEFAULT_MODEL,
    NormalizedLlmRequest,
    build_openai_responses_request,
)

DEFAULT_PROVIDER = "openai"
DEFAULT_ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_ANTHROPIC_MAX_TOKENS = 1024
_OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
_OPENAI_CONVERSATIONS_URL = "https://api.openai.com/v1/conversations"
_ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages"
_GEMINI_GENERATE_CONTENT_URL_TEMPLATE = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)


class LlmProviderAdapter:
    name = ""

    # Providers normalize upstream responses back into the app's existing
    # OpenAI Responses-compatible JSON contract.
    def forward_request(
        self,
        *,
        api_key: str,
        request_body: NormalizedLlmRequest,
        timeout_seconds: int,
    ) -> Dict[str, Any]:
        raise NotImplementedError


class OpenAiResponsesProvider(LlmProviderAdapter):
    name = DEFAULT_PROVIDER

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: NormalizedLlmRequest,
        timeout_seconds: int,
    ) -> Dict[str, Any]:
        started_at = time.perf_counter()
        upstream_body = build_openai_responses_request(request_body)
        status_code, response_body = _post_json_request(
            url=_OPENAI_RESPONSES_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            body=upstream_body,
            timeout_seconds=timeout_seconds,
            fallback_error_message="OpenAI upstream error",
        )
        conversation_id = str(upstream_body.get("conversation") or "").strip()
        appended_tool_outputs = 0
        if 200 <= status_code < 300 and conversation_id:
            appended_tool_outputs = append_openai_function_call_outputs(
                api_key=api_key,
                conversation_id=conversation_id,
                response_body=response_body,
                timeout_seconds=timeout_seconds,
            )
        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        return {
            **_json_response(status_code, response_body),
            "observability": {
                "provider_roundtrip_ms": elapsed_ms,
                "openai_api_ms": elapsed_ms,
                "openai_conversation_tool_outputs_appended": appended_tool_outputs
                or None,
            },
        }


class AnthropicMessagesProvider(LlmProviderAdapter):
    name = "claude"

    def _build_upstream_request(
        self,
        request_body: NormalizedLlmRequest,
    ) -> Dict[str, Any]:
        system_prompt, messages = _split_system_instruction_and_messages(request_body)
        body: Dict[str, Any] = {
            "model": str(request_body.get("model") or DEFAULT_MODEL).strip(),
            "messages": [
                {
                    "role": "assistant" if message["role"] == "assistant" else "user",
                    "content": message["content"],
                }
                for message in messages
            ],
            "max_tokens": _anthropic_max_tokens(request_body),
        }

        if system_prompt:
            body["system"] = system_prompt

        temperature = request_body.get("temperature")
        if isinstance(temperature, (int, float)):
            body["temperature"] = max(0.0, min(float(temperature), 1.0))

        tools = _build_anthropic_tools(request_body.get("tools"))
        if tools:
            body["tools"] = tools
            tool_choice = _build_anthropic_tool_choice(request_body.get("tool_choice"))
            if tool_choice is not None:
                body["tool_choice"] = tool_choice

        return body

    def _normalize_success_payload(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        outputs: List[Dict[str, Any]] = []
        text_buffer: List[str] = []

        for block in payload.get("content") or []:
            if not isinstance(block, dict):
                continue

            block_type = str(block.get("type") or "").strip()
            if block_type == "text":
                text = block.get("text")
                if isinstance(text, str) and text.strip():
                    text_buffer.append(text.strip())
                continue

            if block_type == "tool_use":
                _flush_text_buffer(outputs, text_buffer)
                name = block.get("name")
                if not isinstance(name, str) or not name.strip():
                    continue
                outputs.append(
                    _normalized_function_call(
                        name=name.strip(),
                        arguments=block.get("input") or {},
                    )
                )

        _flush_text_buffer(outputs, text_buffer)
        usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else {}
        input_tokens = int(usage.get("input_tokens") or 0)
        output_tokens = int(usage.get("output_tokens") or 0)
        return {
            "id": payload.get("id"),
            "model": payload.get("model"),
            "output": outputs,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": int(usage.get("total_tokens") or (input_tokens + output_tokens)),
            },
        }

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: NormalizedLlmRequest,
        timeout_seconds: int,
    ) -> Dict[str, Any]:
        started_at = time.perf_counter()
        status_code, response_body = _post_json_request(
            url=_ANTHROPIC_MESSAGES_URL,
            headers={
                "x-api-key": api_key,
                "anthropic-version": _anthropic_version(),
                "Content-Type": "application/json",
            },
            body=self._build_upstream_request(request_body),
            timeout_seconds=timeout_seconds,
            fallback_error_message="Anthropic upstream error",
        )
        if status_code >= 400:
            elapsed_ms = int((time.perf_counter() - started_at) * 1000)
            return {
                **_json_response(status_code, response_body),
                "observability": {
                    "provider_roundtrip_ms": elapsed_ms,
                },
            }

        payload = _parse_json_object(response_body)
        normalized = self._normalize_success_payload(payload)
        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        return {
            **_json_response(status_code, json.dumps(normalized)),
            "observability": {
                "provider_roundtrip_ms": elapsed_ms,
            },
        }


class GeminiGenerateContentProvider(LlmProviderAdapter):
    name = "gemini"

    def _build_upstream_request(
        self,
        request_body: NormalizedLlmRequest,
    ) -> Dict[str, Any]:
        system_prompt, messages = _split_system_instruction_and_messages(request_body)
        body: Dict[str, Any] = {
            "contents": [
                {
                    "role": "model" if message["role"] == "assistant" else "user",
                    "parts": [{"text": message["content"]}],
                }
                for message in messages
            ],
        }

        if system_prompt:
            body["systemInstruction"] = {
                "parts": [{"text": system_prompt}],
            }

        generation_config: Dict[str, Any] = {}
        temperature = request_body.get("temperature")
        if isinstance(temperature, (int, float)):
            generation_config["temperature"] = max(0.0, min(float(temperature), 2.0))

        max_output_tokens = request_body.get("max_output_tokens")
        if isinstance(max_output_tokens, int) and max_output_tokens > 0:
            generation_config["maxOutputTokens"] = max_output_tokens

        if generation_config:
            body["generationConfig"] = generation_config

        tools = _build_gemini_tools(request_body.get("tools"))
        if tools:
            body["tools"] = [{"functionDeclarations": tools}]
            tool_config = _build_gemini_tool_config(request_body.get("tool_choice"))
            if tool_config is not None:
                body["toolConfig"] = tool_config

        return body

    def _build_url(self, model: str) -> str:
        normalized_model = model.strip() or DEFAULT_MODEL
        return _GEMINI_GENERATE_CONTENT_URL_TEMPLATE.format(
            model=urllib.parse.quote(normalized_model, safe="")
        )

    def _normalize_success_payload(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        outputs: List[Dict[str, Any]] = []
        candidates = payload.get("candidates")
        if not isinstance(candidates, list):
            return {"output": outputs}

        for candidate in candidates:
            if not isinstance(candidate, dict):
                continue
            content = candidate.get("content")
            if not isinstance(content, dict):
                continue

            text_buffer: List[str] = []
            for part in content.get("parts") or []:
                if not isinstance(part, dict):
                    continue

                text = part.get("text")
                if isinstance(text, str) and text.strip():
                    text_buffer.append(text.strip())

                function_call = part.get("functionCall") or part.get("function_call")
                if isinstance(function_call, dict):
                    _flush_text_buffer(outputs, text_buffer)
                    name = function_call.get("name")
                    if not isinstance(name, str) or not name.strip():
                        continue
                    outputs.append(
                        _normalized_function_call(
                            name=name.strip(),
                            arguments=function_call.get("args") or {},
                        )
                    )

            _flush_text_buffer(outputs, text_buffer)
            if outputs:
                break

        usage_metadata = payload.get("usageMetadata")
        if not isinstance(usage_metadata, dict):
            usage_metadata = {}
        input_tokens = int(usage_metadata.get("promptTokenCount") or 0)
        output_tokens = int(usage_metadata.get("candidatesTokenCount") or 0)

        return {
            "model": payload.get("modelVersion") or payload.get("model"),
            "output": outputs,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": int(
                    usage_metadata.get("totalTokenCount")
                    or (input_tokens + output_tokens)
                ),
            },
        }

    def forward_request(
        self,
        *,
        api_key: str,
        request_body: NormalizedLlmRequest,
        timeout_seconds: int,
    ) -> Dict[str, Any]:
        started_at = time.perf_counter()
        model = str(request_body.get("model") or DEFAULT_MODEL)
        status_code, response_body = _post_json_request(
            url=self._build_url(model),
            headers={
                "x-goog-api-key": api_key,
                "Content-Type": "application/json",
            },
            body=self._build_upstream_request(request_body),
            timeout_seconds=timeout_seconds,
            fallback_error_message="Gemini upstream error",
        )
        if status_code >= 400:
            elapsed_ms = int((time.perf_counter() - started_at) * 1000)
            return {
                **_json_response(status_code, response_body),
                "observability": {
                    "provider_roundtrip_ms": elapsed_ms,
                },
            }

        payload = _parse_json_object(response_body)
        normalized = self._normalize_success_payload(payload)
        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        return {
            **_json_response(status_code, json.dumps(normalized)),
            "observability": {
                "provider_roundtrip_ms": elapsed_ms,
            },
        }


_PROVIDER_REGISTRY = {
    DEFAULT_PROVIDER: OpenAiResponsesProvider(),
    "claude": AnthropicMessagesProvider(),
    "gemini": GeminiGenerateContentProvider(),
}
_PROVIDER_ALIASES = {
    "openai": DEFAULT_PROVIDER,
    "openai-responses": DEFAULT_PROVIDER,
    "openai_responses": DEFAULT_PROVIDER,
    "anthropic": "claude",
    "google": "gemini",
}


def get_provider(name: str) -> LlmProviderAdapter:
    normalized_name = _PROVIDER_ALIASES.get(name.strip().lower(), name.strip().lower())
    provider = _PROVIDER_REGISTRY.get(normalized_name)
    if provider is None:
        supported = ", ".join(sorted(_PROVIDER_REGISTRY))
        raise ValueError(
            f"Unsupported LLM provider '{name}'. Supported providers: {supported}."
        )
    return provider


def _anthropic_version() -> str:
    raw = os.environ.get("ANTHROPIC_VERSION", "").strip()
    return raw or DEFAULT_ANTHROPIC_VERSION


def _anthropic_max_tokens(request_body: NormalizedLlmRequest) -> int:
    max_output_tokens = request_body.get("max_output_tokens")
    if isinstance(max_output_tokens, int) and max_output_tokens > 0:
        return max_output_tokens
    return DEFAULT_ANTHROPIC_MAX_TOKENS


def _split_system_instruction_and_messages(
    request_body: NormalizedLlmRequest,
) -> Tuple[str, List[Dict[str, str]]]:
    instructions: List[str] = []
    base_instructions = request_body.get("instructions")
    if isinstance(base_instructions, str) and base_instructions.strip():
        instructions.append(base_instructions.strip())

    messages: List[Dict[str, str]] = []
    for message in request_body.get("messages") or []:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role") or "").strip().lower()
        content = message.get("content")
        if not isinstance(content, str) or not content:
            continue

        if role == "system":
            if content.strip():
                instructions.append(content.strip())
            continue

        messages.append(
            {
                "role": "assistant" if role == "assistant" else "user",
                "content": content,
            }
        )

    return "\n\n".join(part for part in instructions if part), messages


def _build_anthropic_tools(value: Any) -> List[Dict[str, Any]]:
    if not isinstance(value, list):
        return []

    tools: List[Dict[str, Any]] = []
    for tool in value:
        if not isinstance(tool, dict):
            continue
        name = tool.get("name")
        parameters = tool.get("parameters")
        if not isinstance(name, str) or not name.strip() or not isinstance(parameters, dict):
            continue

        normalized_tool = {
            "name": name.strip(),
            "input_schema": parameters,
        }
        description = tool.get("description")
        if isinstance(description, str) and description.strip():
            normalized_tool["description"] = description.strip()
        tools.append(normalized_tool)

    return tools


def _build_gemini_tools(value: Any) -> List[Dict[str, Any]]:
    if not isinstance(value, list):
        return []

    tools: List[Dict[str, Any]] = []
    for tool in value:
        if not isinstance(tool, dict):
            continue
        name = tool.get("name")
        parameters = tool.get("parameters")
        if not isinstance(name, str) or not name.strip() or not isinstance(parameters, dict):
            continue

        normalized_tool = {
            "name": name.strip(),
            "parameters": parameters,
        }
        description = tool.get("description")
        if isinstance(description, str) and description.strip():
            normalized_tool["description"] = description.strip()
        tools.append(normalized_tool)

    return tools


def _build_anthropic_tool_choice(value: Any) -> Dict[str, Any] | None:
    if value is None:
        return None

    forced_name = _extract_forced_tool_name(value)
    if forced_name:
        return {"type": "tool", "name": forced_name}

    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"required", "any"}:
            return {"type": "any"}
        if normalized in {"auto", "none"}:
            return {"type": normalized}

    if isinstance(value, dict):
        normalized = str(value.get("type") or "").strip().lower()
        if normalized in {"auto", "none"}:
            return {"type": normalized}

    return None


def _build_gemini_tool_config(value: Any) -> Dict[str, Any] | None:
    if value is None:
        return None

    forced_name = _extract_forced_tool_name(value)
    if forced_name:
        return {
            "functionCallingConfig": {
                "mode": "ANY",
                "allowedFunctionNames": [forced_name],
            }
        }

    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"required", "any"}:
            return {"functionCallingConfig": {"mode": "ANY"}}
        if normalized == "auto":
            return {"functionCallingConfig": {"mode": "AUTO"}}
        if normalized == "none":
            return {"functionCallingConfig": {"mode": "NONE"}}

    if isinstance(value, dict):
        normalized = str(value.get("type") or "").strip().lower()
        if normalized == "auto":
            return {"functionCallingConfig": {"mode": "AUTO"}}
        if normalized == "none":
            return {"functionCallingConfig": {"mode": "NONE"}}

    return None


def _extract_forced_tool_name(value: Any) -> str | None:
    if not isinstance(value, dict):
        return None

    name = value.get("name")
    if isinstance(name, str) and name.strip():
        return name.strip()

    function_value = value.get("function")
    if isinstance(function_value, dict):
        nested_name = function_value.get("name")
        if isinstance(nested_name, str) and nested_name.strip():
            return nested_name.strip()

    return None


def _normalized_output_text_message(text: str) -> Dict[str, Any]:
    return {
        "type": "message",
        "content": [
            {
                "type": "output_text",
                "text": text,
            }
        ],
    }


def _normalized_function_call(name: str, arguments: Any) -> Dict[str, Any]:
    normalized_arguments = arguments if isinstance(arguments, dict) else {"value": arguments}
    return {
        "type": "function_call",
        "name": name,
        "arguments": normalized_arguments,
    }


def _flush_text_buffer(outputs: List[Dict[str, Any]], text_buffer: List[str]) -> None:
    text = "\n\n".join(part for part in text_buffer if part).strip()
    if text:
        outputs.append(_normalized_output_text_message(text))
    text_buffer.clear()


def _parse_json_object(body: str) -> Dict[str, Any]:
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return {}
    if isinstance(payload, dict):
        return payload
    return {}


def _openai_headers(api_key: str) -> Dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def create_openai_conversation(
    *,
    api_key: str,
    metadata: Dict[str, Any] | None = None,
    seed_items: List[Dict[str, Any]] | None = None,
    timeout_seconds: int,
) -> str:
    body: Dict[str, Any] = {}
    if metadata:
        body["metadata"] = metadata
    if seed_items:
        body["items"] = seed_items[:20]

    status_code, response_body = _post_json_request(
        url=_OPENAI_CONVERSATIONS_URL,
        headers=_openai_headers(api_key),
        body=body,
        timeout_seconds=timeout_seconds,
        fallback_error_message="OpenAI conversation create error",
    )
    payload = _parse_json_object(response_body)
    conversation_id = str(payload.get("id") or "").strip()
    if status_code < 200 or status_code >= 300 or not conversation_id:
        raise RuntimeError(
            f"OpenAI conversation create failed with status {status_code}."
        )
    return conversation_id


def append_openai_conversation_items(
    *,
    api_key: str,
    conversation_id: str,
    items: List[Dict[str, Any]],
    timeout_seconds: int,
) -> bool:
    normalized_id = conversation_id.strip()
    if not normalized_id or not items:
        return False

    status_code, _response_body = _post_json_request(
        url=f"{_OPENAI_CONVERSATIONS_URL}/{urllib.parse.quote(normalized_id, safe='')}/items",
        headers=_openai_headers(api_key),
        body={"items": items[:20]},
        timeout_seconds=timeout_seconds,
        fallback_error_message="OpenAI conversation item append error",
    )
    return 200 <= status_code < 300


def _function_call_output_items_from_response(response_body: str) -> List[Dict[str, Any]]:
    payload = _parse_json_object(response_body)
    output = payload.get("output")
    if not isinstance(output, list):
        return []

    items: List[Dict[str, Any]] = []
    for item in output:
        if not isinstance(item, dict):
            continue
        if str(item.get("type") or "").strip() != "function_call":
            continue
        call_id = str(item.get("call_id") or "").strip()
        if not call_id:
            continue
        name = str(item.get("name") or "tool").strip() or "tool"
        items.append(
            {
                "type": "function_call_output",
                "call_id": call_id,
                "output": json.dumps(
                    {
                        "status": "queued_for_mixroom_execution",
                        "message": (
                            "Mixroom accepted this tool call for app-side "
                            "execution. Fresh PROJECT_SNAPSHOT in the next "
                            "request is authoritative for what actually changed."
                        ),
                        "tool_name": name,
                    },
                    separators=(",", ":"),
                ),
            }
        )
    return items


def append_openai_function_call_outputs(
    *,
    api_key: str,
    conversation_id: str,
    response_body: str,
    timeout_seconds: int,
) -> int:
    items = _function_call_output_items_from_response(response_body)
    if not items:
        return 0
    try:
        appended = append_openai_conversation_items(
            api_key=api_key,
            conversation_id=conversation_id,
            items=items,
            timeout_seconds=timeout_seconds,
        )
    except Exception:
        return 0
    return len(items) if appended else 0


def _network_retry_attempts() -> int:
    raw = os.environ.get("LLM_UPSTREAM_NETWORK_RETRY_ATTEMPTS", "2").strip() or "2"
    try:
        attempts = int(raw)
    except ValueError:
        return 2
    return max(attempts, 1)


def _retry_backoff_seconds(attempt_index: int) -> float:
    capped_index = max(attempt_index, 0)
    return min(0.25 * (2**capped_index), 1.0)


def _is_retryable_transport_error(error: BaseException) -> bool:
    if isinstance(error, TimeoutError):
        return True
    if isinstance(error, socket.timeout):
        return True
    if isinstance(error, urllib.error.URLError):
        reason = error.reason
        if isinstance(reason, (TimeoutError, socket.timeout)):
            return True
        if isinstance(
            reason,
            (
                ConnectionError,
                ConnectionRefusedError,
                ConnectionResetError,
                socket.gaierror,
                socket.herror,
                OSError,
            ),
        ):
            return True
        reason_text = str(reason or "").lower()
        return any(
            marker in reason_text
            for marker in (
                "timed out",
                "temporary failure",
                "name resolution",
                "connection refused",
                "connection reset",
                "network is unreachable",
                "connection aborted",
            )
        )
    return isinstance(error, (ConnectionError, ConnectionRefusedError, ConnectionResetError))


def is_upstream_timeout_error(error: BaseException) -> bool:
    if isinstance(error, (TimeoutError, socket.timeout)):
        return True
    if isinstance(error, urllib.error.URLError):
        reason = error.reason
        if isinstance(reason, (TimeoutError, socket.timeout)):
            return True
        return "timed out" in str(reason or "").lower()
    return False


def encode_json_request_body(body: Dict[str, Any]) -> bytes:
    return json.dumps(body, ensure_ascii=False).encode("utf-8")


def _post_json_request(
    *,
    url: str,
    headers: Dict[str, str],
    body: Dict[str, Any],
    timeout_seconds: int,
    fallback_error_message: str,
) -> Tuple[int, str]:
    payload = encode_json_request_body(body)
    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers=headers,
    )

    attempts = _network_retry_attempts()
    timeout_budget_seconds = max(float(timeout_seconds), 0.001)
    deadline = time.monotonic() + timeout_budget_seconds
    for attempt_index in range(attempts):
        remaining_seconds = deadline - time.monotonic()
        if remaining_seconds <= 0:
            raise TimeoutError("LLM upstream request deadline exceeded.")
        try:
            with urllib.request.urlopen(
                request,
                timeout=max(min(timeout_budget_seconds, remaining_seconds), 0.001),
            ) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            body_text = error.read().decode("utf-8") if error.fp else ""
            if not body_text:
                body_text = json.dumps({"error": fallback_error_message})
            return error.code, body_text
        except Exception as error:
            is_last_attempt = attempt_index >= attempts - 1
            if is_last_attempt or not _is_retryable_transport_error(error):
                raise
            retry_backoff = _retry_backoff_seconds(attempt_index)
            if deadline - time.monotonic() <= retry_backoff:
                if is_upstream_timeout_error(error):
                    raise TimeoutError(
                        "LLM upstream request deadline exceeded."
                    ) from error
                raise
            time.sleep(retry_backoff)

    raise RuntimeError("LLM upstream transport retry loop exhausted unexpectedly.")


def _json_response(status_code: int, body: str) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": body,
    }
