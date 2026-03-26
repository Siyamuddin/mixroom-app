from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Any

from . import config
from .secrets import load_postmark_server_token

_logger = logging.getLogger(__name__)
_POSTMARK_INACTIVE_RECIPIENT_ERROR_CODE = 406


class EmailDeliveryError(RuntimeError):
    pass


class EmailSuppressedError(EmailDeliveryError):
    def __init__(self, *, email: str, reason: str = "") -> None:
        self.email = str(email or "").strip().lower()
        self.reason = str(reason or "").strip().upper()
        reason_suffix = f" ({self.reason})" if self.reason else ""
        super().__init__(f"Email address is suppressed{reason_suffix}.")


def _is_suppressed_error(*, error_code: int, message: str) -> bool:
    if error_code == _POSTMARK_INACTIVE_RECIPIENT_ERROR_CODE:
        return True
    safe_message = str(message or "").strip().lower()
    return "inactive recipient" in safe_message or "suppressed" in safe_message


def _load_postmark_token() -> str:
    try:
        return load_postmark_server_token()
    except Exception as exc:
        raise EmailDeliveryError("Postmark is not configured.") from exc


def _postmark_endpoint() -> str:
    base_url = str(config.POSTMARK_API_BASE_URL or "").strip().rstrip("/")
    if not base_url:
        base_url = "https://api.postmarkapp.com"
    return f"{base_url}/email"


def _parse_postmark_response(payload: bytes) -> dict[str, Any]:
    if not payload:
        return {}
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except Exception:
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _postmark_error_code(response_payload: dict[str, Any]) -> int:
    try:
        return int(response_payload.get("ErrorCode") or 0)
    except (TypeError, ValueError):
        return 0


def send_auth_email(
    *,
    to_email: str,
    subject: str,
    text_body: str,
    html_body: str = "",
) -> None:
    sender = config.APP_AUTH_EMAIL_FROM_ADDRESS
    if not sender:
        raise EmailDeliveryError("APP_AUTH_EMAIL_FROM_ADDRESS is not configured.")
    token = _load_postmark_token()

    payload: dict[str, Any] = {
        "From": sender,
        "To": str(to_email or "").strip(),
        "Subject": subject,
        "TextBody": text_body,
    }
    if html_body.strip():
        payload["HtmlBody"] = html_body
    reply_to = config.APP_AUTH_EMAIL_REPLY_TO_ADDRESS
    if reply_to:
        payload["ReplyTo"] = reply_to
    if config.POSTMARK_MESSAGE_STREAM:
        payload["MessageStream"] = config.POSTMARK_MESSAGE_STREAM

    request = urllib.request.Request(
        _postmark_endpoint(),
        data=json.dumps(payload, ensure_ascii=True).encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Postmark-Server-Token": token,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=config.HTTP_TIMEOUT_SECONDS) as response:
            response_payload = _parse_postmark_response(response.read())
            error_code = _postmark_error_code(response_payload)
            if error_code:
                message = str(response_payload.get("Message") or "").strip()
                if _is_suppressed_error(error_code=error_code, message=message):
                    raise EmailSuppressedError(email=to_email, reason="INACTIVE")
                raise EmailDeliveryError("Failed to send auth email.")
            message_id = str(response_payload.get("MessageID") or "").strip()
            if not message_id:
                _logger.warning(
                    "Postmark email request completed without MessageID.",
                    extra={
                        "from_address": sender,
                        "to_domain": str(to_email or "").split("@")[-1].lower(),
                    },
                )
    except EmailSuppressedError:
        raise
    except urllib.error.HTTPError as exc:
        response_payload = _parse_postmark_response(exc.read())
        error_code = _postmark_error_code(response_payload)
        message = str(response_payload.get("Message") or "").strip()
        if _is_suppressed_error(error_code=error_code, message=message):
            raise EmailSuppressedError(email=to_email, reason="INACTIVE") from exc
        _logger.exception(
            "Auth email delivery failed via Postmark.",
            extra={
                "from_address": sender,
                "to_domain": str(to_email or "").split("@")[-1].lower(),
                "http_status": exc.code,
                "postmark_error_code": error_code,
            },
        )
        raise EmailDeliveryError("Failed to send auth email.") from exc
    except Exception as exc:
        _logger.exception(
            "Auth email delivery failed via Postmark.",
            extra={
                "from_address": sender,
                "to_domain": str(to_email or "").split("@")[-1].lower(),
            },
        )
        raise EmailDeliveryError("Failed to send auth email.") from exc
