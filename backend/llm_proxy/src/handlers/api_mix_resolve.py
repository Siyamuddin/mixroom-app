from __future__ import annotations

import json
import time
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.mix_resolve import (
    MixResolveService,
    MixResolveValidationError,
    contract_version,
)
from common.monitoring import capture_exception, init_sentry

init_sentry("mixroom-llm-proxy")

_resolver = MixResolveService()


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.time()
    user_id = extract_user_id_from_event(event)
    if not user_id:
        return unauthorized()

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return json_response(400, {"error": "Invalid JSON body."})

    if not isinstance(body, dict):
        return json_response(400, {"error": "Request body must be an object."})

    project = body.get("project_state")
    if not isinstance(project, dict):
        project = body.get("project")
    goal = body.get("goal")
    actions = body.get("actions")
    strict = body.get("strict")
    requested_contract_version = str(
        body.get("mix_feature_contract_version")
        or body.get("feature_contract_version")
        or ""
    ).strip()
    if not isinstance(project, dict):
        return json_response(400, {"error": "'project' must be an object."})
    if not isinstance(goal, dict):
        return json_response(400, {"error": "'goal' must be an object."})
    if not isinstance(actions, list):
        return json_response(400, {"error": "'actions' must be a list."})
    if not isinstance(strict, bool):
        return json_response(400, {"error": "'strict' must be a boolean."})
    if requested_contract_version and requested_contract_version != contract_version():
        return json_response(
            400,
            {
                "error": "mix_feature_contract_version_mismatch",
                "expected": contract_version(),
                "received": requested_contract_version,
            },
        )

    try:
        normalized_actions = [_normalize_action_payload(action) for action in actions]
        resolved = _resolver.resolve(
            project=project,
            goal=goal,
            actions=normalized_actions,
            strict=strict,
        )
    except MixResolveValidationError as error:
        _log_mix_resolve_event(
            status="validation_error",
            user_id=user_id,
            project_id=str(body.get("project_id") or "").strip(),
            input_action_count=len(actions),
            output_action_count=0,
            duration_ms=int((time.time() - started_at) * 1000.0),
            fallback_used=True,
            fallback_reason=str(error),
            debug_entries=[],
            observability={},
        )
        return json_response(400, {"error": str(error)})
    except Exception as error:  # pragma: no cover - sentry/logging path
        capture_exception(
            error,
            context={
                "service": "llm_proxy",
                "handler": "api_mix_resolve",
                "user_id": user_id,
                "project_id": str(body.get("project_id") or "").strip(),
                "app_version": str(
                    ((body.get("client_context") or {}).get("app_version") or "")
                ).strip(),
            },
            tags={"service": "llm_proxy", "route": "mix_resolve"},
        )
        _log_mix_resolve_event(
            status="server_error",
            user_id=user_id,
            project_id=str(body.get("project_id") or "").strip(),
            input_action_count=len(actions),
            output_action_count=0,
            duration_ms=int((time.time() - started_at) * 1000.0),
            fallback_used=True,
            fallback_reason="mix_refine_failed",
            debug_entries=[],
            observability={},
        )
        return json_response(500, {"error": "mix_refine_failed"})

    elapsed_ms = int((time.time() - started_at) * 1000.0)
    _log_mix_resolve_event(
        status="ok",
        user_id=user_id,
        project_id=str(body.get("project_id") or "").strip(),
        input_action_count=len(normalized_actions),
        output_action_count=len(resolved["actions"]),
        duration_ms=elapsed_ms,
        fallback_used=resolved.get("fallback_used") == True,
        fallback_reason=str(resolved.get("fallback_reason") or ""),
        debug_entries=resolved.get("debug_entries") or [],
        observability=resolved.get("observability") or {},
    )
    return json_response(
        200,
        {
            "actions": resolved["actions"],
            "debug_entries": resolved["debug_entries"],
            "fallback_used": resolved.get("fallback_used") == True,
            "fallback_reason": str(resolved.get("fallback_reason") or ""),
            "observability": resolved["observability"],
            "request_duration_ms": elapsed_ms,
        },
    )


def _normalize_action_payload(raw: Any) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        raise MixResolveValidationError("Each action must be an object.")
    action_type = str(raw.get("type") or "").strip()
    data = raw.get("data")
    if not action_type:
        raise MixResolveValidationError("Each action must include a non-empty type.")
    if not isinstance(data, dict):
        raise MixResolveValidationError("Each action must include a data object.")
    return {"type": action_type, "data": dict(data)}


def _log_mix_resolve_event(
    *,
    status: str,
    user_id: str,
    project_id: str,
    input_action_count: int,
    output_action_count: int,
    duration_ms: int,
    fallback_used: bool,
    fallback_reason: str,
    debug_entries: list[dict[str, Any]],
    observability: dict[str, Any],
) -> None:
    scales = [
        float(entry.get("final_scale"))
        for entry in debug_entries
        if isinstance(entry, dict) and isinstance(entry.get("final_scale"), (int, float))
    ]
    dropped_count = sum(
        1
        for entry in debug_entries
        if isinstance(entry, dict) and entry.get("dropped") == True
    )
    payload = {
        "handler": "api_mix_resolve",
        "status": status,
        "user_id": user_id,
        "project_id": project_id,
        "input_action_count": input_action_count,
        "output_action_count": output_action_count,
        "debug_entry_count": len(debug_entries),
        "dropped_action_count": dropped_count,
        "duration_ms": duration_ms,
        "fallback_used": fallback_used,
        "fallback_reason": fallback_reason,
        "mix_model_onnx_ms": observability.get("mix_model_onnx_ms"),
        "mix_model_source": observability.get("mix_magnitude_model_source"),
        "mix_model_bundle_version": observability.get(
            "mix_magnitude_model_bundle_version"
        ),
        "adjustment_scale_avg": (
            round(sum(scales) / len(scales), 4) if scales else None
        ),
        "adjustment_scale_max": (round(max(scales), 4) if scales else None),
    }
    print(json.dumps(payload, ensure_ascii=False))
