from __future__ import annotations

from typing import Any, Dict

from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.project_telemetry_repository import ProjectTelemetryRepository
from common.rate_limits import RequestRateLimiter, client_ip_from_event
from common.repository import BillingRepository

repo = ProjectTelemetryRepository()
user_repo = BillingRepository()
rate_limiter = RequestRateLimiter()
_MAX_PROJECT_TELEMETRY_REQUEST_BYTES = 2_000_000


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _rate_limited_response(retry_after_seconds: int) -> Dict[str, Any]:
    retry_after = max(1, int(retry_after_seconds or 0))
    return json_response(
        429,
        {
            "error": "Too many telemetry uploads. Please try again later.",
            "code": "RATE_LIMITED",
            "retry_after_seconds": retry_after,
        },
        headers={"Retry-After": str(retry_after)},
    )


def _sanitize_project_json(project_json: Dict[str, Any], *, include_chat: bool) -> Dict[str, Any]:
    sanitized = dict(project_json)
    if not include_chat:
        sanitized.pop("assistantChat", None)
    return sanitized


def _submit_project_telemetry(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not repo.is_configured:
        return json_response(503, {"error": "Project telemetry service is not configured."})

    user_decision = rate_limiter.enforce(
        scope_key=f"project_telemetry:user:{user_id}",
        limit=48,
        window_seconds=3600,
        block_seconds=300,
    )
    if not user_decision.allowed:
        return _rate_limited_response(user_decision.retry_after_seconds)

    client_ip = client_ip_from_event(event)
    if client_ip:
        ip_decision = rate_limiter.enforce(
            scope_key=f"project_telemetry:ip:{client_ip}",
            limit=120,
            window_seconds=3600,
            block_seconds=300,
        )
        if not ip_decision.allowed:
            return _rate_limited_response(ip_decision.retry_after_seconds)

    try:
        body = parse_json_body(
            event,
            max_bytes=_MAX_PROJECT_TELEMETRY_REQUEST_BYTES,
        )
    except RequestBodyError as exc:
        return json_response(exc.status_code, {"error": exc.message})

    project_json = body.get("project_json")
    if not isinstance(project_json, dict):
        return json_response(400, {"error": "project_json is required."})

    user_profile = user_repo.get_user_profile(user_id) or {}
    telemetry_enabled = user_profile.get("telemetry_enabled")
    include_chat = telemetry_enabled is not False

    project_id = str(
        body.get("project_id")
        or project_json.get("projectId")
        or project_json.get("project_id")
        or "unknown-project"
    ).strip() or "unknown-project"
    sanitized_project_json = _sanitize_project_json(
        project_json,
        include_chat=include_chat,
    )

    envelope = {
        "schema_version": 1,
        "uploaded_at": body.get("uploaded_at"),
        "source": str(body.get("source") or "audio_editor_save").strip()
        or "audio_editor_save",
        "telemetry_enabled": telemetry_enabled is not False,
        "includes_assistant_chat": include_chat,
        "user_id": user_id,
        "client_context": body.get("client_context")
        if isinstance(body.get("client_context"), dict)
        else {},
        "project_id": project_id,
        "project_name": body.get("project_name"),
        "project_snapshot": body.get("project_snapshot")
        if isinstance(body.get("project_snapshot"), dict)
        else {},
        "project_json": sanitized_project_json,
    }

    stored = repo.store_snapshot(
        user_id=user_id,
        payload=envelope,
        project_id=project_id,
    )
    return json_response(
        202,
        {
            "accepted": True,
            "project_id": project_id,
            "stored_at": stored["stored_at"],
            "object_id": stored["object_id"],
        },
    )


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    method = _method(event)

    if method == "POST" and path.endswith("/v1/telemetry/project-snapshots"):
        return _submit_project_telemetry(event)

    return json_response(404, {"error": "Not found"})
