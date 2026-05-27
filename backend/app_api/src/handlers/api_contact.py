from __future__ import annotations

import json
import re
from email.utils import parseaddr
from typing import Any, Dict

from common.email_delivery import EmailDeliveryError, send_postmark_email
from common.events import RequestBodyError, parse_json_body
from common.monitoring import capture_exception, init_sentry
from common.rate_limits import RequestRateLimiter, client_ip_from_event

init_sentry("mixroom-app-api-contact")

rate_limiter = RequestRateLimiter()

_ALLOWED_ORIGINS = {"https://www.mixroom.ai", "https://mixroom.ai"}
_SOURCE_ROUTES = {
    "contact": {
        "from_email": "fromcontactpage@mixroom.ai",
        "to_email": "contact@mixroom.ai",
    },
    "support": {
        "from_email": "fromsupportpage@mixroom.ai",
        "to_email": "support@mixroom.ai",
    },
}
_MAX_CONTACT_REQUEST_BYTES = 20000
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _origin(event: Dict[str, Any]) -> str:
    headers = event.get("headers") or {}
    return str(headers.get("origin") or headers.get("Origin") or "").strip()


def _cors_headers(event: Dict[str, Any]) -> Dict[str, str]:
    origin = _origin(event)
    if origin not in _ALLOWED_ORIGINS:
        return {}
    return {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Accept",
        "Vary": "Origin",
    }


def _json_response(
    status_code: int,
    body: Dict[str, Any],
    event: Dict[str, Any],
    *,
    headers: Dict[str, str] | None = None,
) -> Dict[str, Any]:
    response_headers = {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        **_cors_headers(event),
    }
    if headers:
        response_headers.update(headers)
    return {
        "statusCode": status_code,
        "headers": response_headers,
        "body": json.dumps(body),
    }


def _empty_response(
    status_code: int,
    event: Dict[str, Any],
    *,
    headers: Dict[str, str] | None = None,
) -> Dict[str, Any]:
    response_headers = {
        "Cache-Control": "no-store",
        **_cors_headers(event),
    }
    if headers:
        response_headers.update(headers)
    return {"statusCode": status_code, "headers": response_headers, "body": ""}


def _has_header_control_chars(value: str) -> bool:
    return "\r" in value or "\n" in value


def _clean_text(value: Any, *, max_length: int) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if len(text) > max_length:
        text = text[:max_length].strip()
    return text


def _clean_email(value: Any) -> str:
    email = _clean_text(value, max_length=254)
    if not email or _has_header_control_chars(email):
        raise ValueError("A valid reply-to email is required.")
    parsed_email = parseaddr(email)[1]
    if parsed_email != email or not _EMAIL_RE.match(email):
        raise ValueError("A valid reply-to email is required.")
    return email


def _validate_payload(payload: Dict[str, Any]) -> Dict[str, str]:
    source = _clean_text(payload.get("source"), max_length=32).lower()
    if source not in _SOURCE_ROUTES:
        raise ValueError("source must be contact or support.")

    subject = _clean_text(payload.get("subject"), max_length=180)
    if not subject:
        raise ValueError("subject is required.")
    if _has_header_control_chars(subject):
        raise ValueError("subject is invalid.")

    message = _clean_text(payload.get("message"), max_length=8000)
    if not message:
        raise ValueError("message is required.")

    return {
        "source": source,
        "subject": subject,
        "message": message,
        "email": _clean_email(payload.get("email")),
        "pageUrl": _clean_text(payload.get("pageUrl"), max_length=1000),
        "locale": _clean_text(payload.get("locale"), max_length=32),
    }


def _rate_limited_response(event: Dict[str, Any], retry_after_seconds: int) -> Dict[str, Any]:
    retry_after = max(1, int(retry_after_seconds or 0))
    return _json_response(
        429,
        {
            "error": "Too many submissions. Please try again later.",
            "code": "RATE_LIMITED",
            "retry_after_seconds": retry_after,
        },
        event,
        headers={"Retry-After": str(retry_after)},
    )


def _enforce_rate_limits(event: Dict[str, Any], *, email: str) -> Dict[str, Any] | None:
    email_decision = rate_limiter.enforce(
        scope_key=f"contact_submit:email:{email.lower()}",
        limit=6,
        window_seconds=3600,
        block_seconds=3600,
    )
    if not email_decision.allowed:
        return _rate_limited_response(event, email_decision.retry_after_seconds)

    client_ip = client_ip_from_event(event)
    if client_ip:
        ip_decision = rate_limiter.enforce(
            scope_key=f"contact_submit:ip:{client_ip}",
            limit=20,
            window_seconds=86400,
            block_seconds=86400,
        )
        if not ip_decision.allowed:
            return _rate_limited_response(event, ip_decision.retry_after_seconds)
    return None


def _build_text_body(payload: Dict[str, str]) -> str:
    context_lines = [
        "",
        "--",
        f"Source: {payload['source']}",
        f"Reply-To: {payload['email']}",
        f"Page URL: {payload['pageUrl'] or '-'}",
        f"Locale: {payload['locale'] or '-'}",
    ]
    return f"{payload['message']}\n" + "\n".join(context_lines)


def _submit_contact(event: Dict[str, Any]) -> Dict[str, Any]:
    origin = _origin(event)
    if origin and origin not in _ALLOWED_ORIGINS:
        return _json_response(403, {"error": "Origin is not allowed."}, event)

    try:
        body = parse_json_body(event, max_bytes=_MAX_CONTACT_REQUEST_BYTES)
    except RequestBodyError as exc:
        return _json_response(exc.status_code, {"error": exc.message}, event)

    try:
        payload = _validate_payload(body)
    except ValueError as exc:
        return _json_response(400, {"error": str(exc)}, event)

    limited = _enforce_rate_limits(event, email=payload["email"])
    if limited is not None:
        return limited

    route = _SOURCE_ROUTES[payload["source"]]
    try:
        send_postmark_email(
            from_email=route["from_email"],
            to_email=route["to_email"],
            reply_to_email=payload["email"],
            subject=payload["subject"],
            text_body=_build_text_body(payload),
        )
    except EmailDeliveryError as exc:
        capture_exception(
            exc,
            context={"source": payload["source"], "page_url": payload["pageUrl"]},
            tags={"service": "contact_api"},
        )
        return _json_response(502, {"error": "Could not send message."}, event)

    return _json_response(200, {"ok": True}, event)


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    path = _path(event)
    method = _method(event)

    if path.endswith("/v1/contact"):
        if method == "OPTIONS":
            origin = _origin(event)
            if origin and origin not in _ALLOWED_ORIGINS:
                return _empty_response(403, event)
            return _empty_response(204, event)
        if method == "POST":
            return _submit_contact(event)

    return _json_response(404, {"error": "Not found"}, event)
