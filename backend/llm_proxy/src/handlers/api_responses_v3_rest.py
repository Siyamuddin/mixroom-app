from __future__ import annotations

import base64
import copy
import json
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response
from common import v3_server_contract
from handlers import api_responses


V3_RESPONSES_PATH = "/v1/llm/v3/responses"
_BODY_PARSE_FAILED = object()


def _rest_method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    return str(
        event.get("httpMethod")
        or request_context.get("httpMethod")
        or ""
    ).strip().upper()


def _rest_path(event: Dict[str, Any]) -> str:
    return str(event.get("path") or "").strip().rstrip("/")


def _parsed_body(event: Dict[str, Any]) -> Any:
    raw_body = event.get("body") or ""
    if not isinstance(raw_body, str):
        return _BODY_PARSE_FAILED
    try:
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        return json.loads(raw_body or "{}")
    except (ValueError, UnicodeDecodeError):
        return _BODY_PARSE_FAILED


def normalize_rest_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Return an HTTP API-shaped copy accepted by the existing V3 handler."""

    normalized = copy.deepcopy(event)
    request_context = normalized.get("requestContext")
    if not isinstance(request_context, dict):
        request_context = {}
        normalized["requestContext"] = request_context

    authorizer = request_context.get("authorizer")
    if not isinstance(authorizer, dict):
        authorizer = {}
        request_context["authorizer"] = authorizer
    rest_claims = authorizer.get("claims")
    if isinstance(rest_claims, dict):
        authorizer["jwt"] = {"claims": copy.deepcopy(rest_claims)}

    request_context["routeKey"] = f"POST {V3_RESPONSES_PATH}"
    request_context["http"] = {
        "method": "POST",
        "path": V3_RESPONSES_PATH,
    }
    normalized["version"] = "2.0"
    normalized["rawPath"] = V3_RESPONSES_PATH
    normalized["path"] = V3_RESPONSES_PATH
    normalized["httpMethod"] = "POST"
    return normalized


def _route_not_found() -> Dict[str, Any]:
    return json_response(
        404,
        {
            "error": {
                "code": "v3_rest_route_not_found",
                "message": "Route not found.",
            }
        },
    )


def _method_not_allowed() -> Dict[str, Any]:
    return json_response(
        405,
        {
            "error": {
                "code": "v3_rest_method_not_allowed",
                "message": "Method not allowed.",
            }
        },
    )


def _contract_unsupported() -> Dict[str, Any]:
    return json_response(
        400,
        {
            "error": {
                "code": "v3_request_contract_unsupported",
                "message": "Unsupported V3 request contract.",
            }
        },
    )


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Accept only REST API v1 POST events for the contract-6 V3 route."""

    if not isinstance(event, dict) or _rest_path(event) != V3_RESPONSES_PATH:
        return _route_not_found()
    if _rest_method(event) != "POST":
        return _method_not_allowed()

    normalized = normalize_rest_event(event)
    if not extract_user_id_from_event(normalized):
        return api_responses.handler(normalized, context)

    body = _parsed_body(normalized)
    if (
        isinstance(body, dict)
        and str(body.get("request_contract") or "").strip()
        != v3_server_contract.REQUEST_CONTRACT
    ):
        return _contract_unsupported()

    return api_responses.handler(normalized, context)
