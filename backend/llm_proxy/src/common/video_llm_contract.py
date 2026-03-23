from __future__ import annotations

from typing import Any, Dict, List

from .llm_settings import DEFAULT_MODEL
DEFAULT_TEMPERATURE = 0.1
NormalizedLlmRequest = Dict[str, Any]

VIDEO_SYSTEM_PROMPT = """
You are Mixroom's video timeline assistant for a lightweight editor.

You do not render media. You only return structured timeline actions that the app can execute.
Think like a practical editor inside CapCut, iMovie, Premiere, or Vegas.

You have two tools:
1. informational_response
2. video_editor_actions

Use informational_response when:
- the user is asking for help or capabilities
- the request is unsupported by the current editor
- the request is too ambiguous to edit safely

Use video_editor_actions when the request clearly maps to timeline edits.

Supported action types:
- clip_edit
  - operations: split, trim, move, duplicate, delete, mute, unmute, set_volume
- transition_edit
  - operations: add, remove, set_duration, set_type
- playhead
  - move the playhead with at_ms
- clarify
  - only when absolutely necessary

Rules:
- Prefer direct execution over questions when the intent is clear.
- Use clip_id, track_id, and transition_id from the snapshot whenever possible.
- Treat the selected clip or transition as the default target when the user does not name another target.
- Keep assistant_message short, practical, and in the same language as the user.
- Never invent unsupported features such as captions, masking, color grading, motion tracking, keyframes, cropping, AI generation, or true speed-ramping. Use informational_response instead.
- Never output plain JSON as chat text.
""".strip()

VIDEO_TOOLS = [
    {
        "type": "function",
        "name": "informational_response",
        "parameters": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                }
            },
            "required": ["message"],
        },
    },
    {
        "type": "function",
        "name": "video_editor_actions",
        "parameters": {
            "type": "object",
            "properties": {
                "assistant_message": {
                    "type": "string",
                },
                "actions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "type": {
                                "type": "string",
                                "enum": [
                                    "clip_edit",
                                    "transition_edit",
                                    "playhead",
                                    "clarify",
                                ],
                            },
                            "data": {
                                "type": "object",
                            },
                        },
                        "required": ["type", "data"],
                    },
                },
            },
            "required": ["assistant_message", "actions"],
        },
    },
]

_ALLOWED_REQUEST_OVERRIDE_FIELDS = {"model", "temperature", "max_output_tokens"}


def _normalize_conversation_item(message: Any, index: int) -> Dict[str, str]:
    if not isinstance(message, dict):
        raise ValueError(f"'conversation[{index}]' must be an object.")

    role = str(message.get("role") or "").strip()
    if not role:
        raise ValueError(f"'conversation[{index}].role' must be a non-empty string.")

    content = message.get("content")
    if not isinstance(content, str):
        raise ValueError(f"'conversation[{index}].content' must be a string.")

    return {"role": role, "content": content}


def _read_required_string(payload: Dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"'{key}' must be a non-empty string.")
    return value


def _read_optional_string(payload: Dict[str, Any], key: str) -> str:
    value = payload.get(key, "")
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ValueError(f"'{key}' must be a string.")
    return value


def _normalize_request_overrides(payload: Dict[str, Any]) -> Dict[str, Any]:
    overrides = payload.get("request_overrides")
    if overrides is None:
        return {}
    if not isinstance(overrides, dict):
        raise ValueError("'request_overrides' must be an object.")

    normalized: Dict[str, Any] = {}
    for key, value in overrides.items():
        if key not in _ALLOWED_REQUEST_OVERRIDE_FIELDS:
            continue

        if key == "model":
            if not isinstance(value, str) or not value.strip():
                raise ValueError("'request_overrides.model' must be a non-empty string.")
            normalized[key] = value.strip()
            continue

        if key == "temperature":
            if not isinstance(value, (int, float)):
                raise ValueError("'request_overrides.temperature' must be numeric.")
            normalized[key] = max(0.0, min(float(value), 2.0))
            continue

        if key == "max_output_tokens":
            if not isinstance(value, int) or value <= 0:
                raise ValueError(
                    "'request_overrides.max_output_tokens' must be a positive integer."
                )
            normalized[key] = value

    return normalized


def _build_input_messages(
    *,
    conversation: List[Dict[str, str]],
    user_text: str,
    project_snapshot: str,
    selection_snapshot: str,
) -> List[Dict[str, str]]:
    messages: List[Dict[str, str]] = [
        *conversation,
        {
            "role": "user",
            "content": f"PROJECT_SNAPSHOT:\n{project_snapshot}",
        },
    ]

    if selection_snapshot.strip():
        messages.append(
            {
                "role": "user",
                "content": f"SELECTION_SNAPSHOT:\n{selection_snapshot}",
            }
        )

    messages.append({"role": "user", "content": user_text})
    return messages


def build_video_editor_llm_request_from_mixroom_payload(
    payload: Dict[str, Any],
    *,
    default_model: str = DEFAULT_MODEL,
) -> NormalizedLlmRequest:
    conversation_value = payload.get("conversation", [])
    if conversation_value is None:
        conversation_value = []
    if not isinstance(conversation_value, list):
        raise ValueError("'conversation' must be a list.")

    conversation = [
        _normalize_conversation_item(message, index)
        for index, message in enumerate(conversation_value)
    ]
    user_text = _read_required_string(payload, "user_text")
    project_snapshot = _read_required_string(payload, "project_snapshot")
    selection_snapshot = _read_optional_string(payload, "selection_snapshot")

    body: NormalizedLlmRequest = {
        "model": default_model.strip() or DEFAULT_MODEL,
        "temperature": DEFAULT_TEMPERATURE,
        "instructions": VIDEO_SYSTEM_PROMPT,
        "messages": _build_input_messages(
            conversation=conversation,
            user_text=user_text,
            project_snapshot=project_snapshot,
            selection_snapshot=selection_snapshot,
        ),
        "tools": VIDEO_TOOLS,
        "tool_choice": "required",
    }
    body.update(_normalize_request_overrides(payload))
    return body
