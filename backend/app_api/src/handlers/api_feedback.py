from __future__ import annotations

from typing import Any, Dict

from common import config
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.events import RequestBodyError, parse_json_body
from common.feedback_repository import FeedbackRepository
from common.rate_limits import RequestRateLimiter, client_ip_from_event

repo = FeedbackRepository()
rate_limiter = RequestRateLimiter()
_MAX_FEEDBACK_REQUEST_BYTES = 350000


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
            "error": "Too many feedback submissions. Please try again later.",
            "code": "RATE_LIMITED",
            "retry_after_seconds": retry_after,
        },
        headers={"Retry-After": str(retry_after)},
    )


def _submit_feedback(event: Dict[str, Any]) -> Dict[str, Any]:
    claims = extract_claims_from_event(event)
    user_id = str(claims.get("sub") or "").strip()
    if not user_id:
        return unauthorized()
    if not config.FEEDBACK_SUBMISSIONS_TABLE:
        return json_response(503, {"error": "Feedback service is not configured."})

    user_decision = rate_limiter.enforce(
        scope_key=f"feedback_submit:user:{user_id}",
        limit=6,
        window_seconds=3600,
        block_seconds=3600,
    )
    if not user_decision.allowed:
        return _rate_limited_response(user_decision.retry_after_seconds)

    client_ip = client_ip_from_event(event)
    if client_ip:
        ip_decision = rate_limiter.enforce(
            scope_key=f"feedback_submit:ip:{client_ip}",
            limit=20,
            window_seconds=86400,
            block_seconds=86400,
        )
        if not ip_decision.allowed:
            return _rate_limited_response(ip_decision.retry_after_seconds)

    try:
        body = parse_json_body(event, max_bytes=_MAX_FEEDBACK_REQUEST_BYTES)
    except RequestBodyError as exc:
        return json_response(exc.status_code, {"error": exc.message})

    try:
        submission = repo.create_submission(
            user_id=user_id,
            claims=claims,
            payload=body,
        )
    except ValueError as exc:
        return json_response(400, {"error": str(exc)})

    return json_response(
        200,
        {
            "submission_id": submission["submission_id"],
            "submitted_at": submission["created_at"],
            "message": "Thank you for your submission!",
        },
    )


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    method = _method(event)

    if method == "POST" and path.endswith("/v1/feedback"):
        return _submit_feedback(event)

    return json_response(404, {"error": "Not found"})
