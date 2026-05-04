from __future__ import annotations

import time
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.collaboration_repository import CollaborationRepository
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = CollaborationRepository()
init_sentry("mixroom-app-api-collaboration")


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    rc = event.get("requestContext") or {}
    http = rc.get("http") or {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _path_param(event: Dict[str, Any], name: str) -> str:
    params = event.get("pathParameters") or {}
    if isinstance(params, dict):
        return str(params.get(name) or "").strip()
    return ""


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    user_id = extract_user_id_from_event(event)
    request_context = build_request_log_context(event, _context, user_id=user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not user_id:
        return _finalize(unauthorized(), error="unauthorized")

    try:
        path = _path(event)
        method = _method(event)
        if method not in {"GET", "PUT"}:
            return _finalize(json_response(404, {"error": "Not found"}), error="not_found")

        snapshot = repo.build_user_access_snapshot(user_id)
        if path.endswith("/v1/organizations/me"):
            return _finalize(
                json_response(
                    200,
                    {
                        "organizations": snapshot.get("organizations") or [],
                        "memberships": snapshot.get("memberships") or [],
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/workspaces/me"):
            return _finalize(
                json_response(
                    200,
                    {
                        "workspaces": snapshot.get("workspaces") or [],
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/cloud-projects/me"):
            return _finalize(
                json_response(
                    200,
                    {
                        "cloud_projects": snapshot.get("cloud_projects") or [],
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.startswith("/v1/cloud-projects/") and not path.endswith("/v1/cloud-projects/me"):
            project_id = _path_param(event, "project_id") or path.rsplit("/", 1)[-1]
            if method == "GET":
                return _finalize(
                    json_response(
                        200,
                        {
                            "cloud_project": repo.get_user_cloud_project(user_id, project_id),
                        },
                    )
                )
            body = parse_json_body(event)
            return _finalize(
                json_response(
                    200,
                    {
                        "cloud_project": repo.update_user_cloud_project(
                            user_id,
                            project_id,
                            body,
                        ),
                    },
                )
            )
        return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
    except RequestBodyError as exc:
        return _finalize(
            json_response(exc.status_code, {"error": exc.message}),
            error="request_body_invalid",
        )
    except PermissionError as exc:
        return _finalize(json_response(403, {"error": str(exc)}), error="forbidden")
    except FileNotFoundError as exc:
        return _finalize(json_response(404, {"error": str(exc)}), error="not_found")
    except ValueError as exc:
        message = str(exc)
        status_code = 409 if "revision conflict" in message.lower() else 400
        error_code = "conflict" if status_code == 409 else "bad_request"
        return _finalize(json_response(status_code, {"error": message}), error=error_code)
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "collaboration"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
