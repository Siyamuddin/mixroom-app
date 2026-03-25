from __future__ import annotations

import logging
from typing import Any

import boto3
from botocore.exceptions import ClientError

from . import config

_ses = boto3.client("sesv2")
_logger = logging.getLogger(__name__)
_SUPPRESSION_NOT_FOUND_CODES = {"NotFoundException", "ResourceNotFoundException"}


class EmailDeliveryError(RuntimeError):
    pass


class EmailSuppressedError(EmailDeliveryError):
    def __init__(self, *, email: str, reason: str = "") -> None:
        self.email = str(email or "").strip().lower()
        self.reason = str(reason or "").strip().upper()
        reason_suffix = f" ({self.reason})" if self.reason else ""
        super().__init__(f"Email address is suppressed{reason_suffix}.")


def _lookup_suppressed_destination(email: str) -> dict[str, Any] | None:
    safe_email = str(email or "").strip().lower()
    if not safe_email:
        return None
    try:
        response = _ses.get_suppressed_destination(EmailAddress=safe_email)
    except ClientError as exc:
        code = str(exc.response.get("Error", {}).get("Code") or "").strip()
        if code in _SUPPRESSION_NOT_FOUND_CODES:
            return None
        _logger.exception(
            "Suppression lookup failed via SES.",
            extra={
                "email_domain": safe_email.split("@")[-1],
                "error_code": code,
            },
        )
        return None
    except Exception:
        _logger.exception(
            "Suppression lookup failed via SES.",
            extra={
                "email_domain": safe_email.split("@")[-1],
            },
        )
        return None
    destination = response.get("SuppressedDestination")
    return destination if isinstance(destination, dict) else None


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
    suppressed = _lookup_suppressed_destination(to_email)
    if suppressed:
        reason = str(suppressed.get("Reason") or "").strip().upper()
        raise EmailSuppressedError(email=to_email, reason=reason)

    destination: dict[str, Any] = {"ToAddresses": [to_email]}
    content = {
        "Simple": {
            "Subject": {"Data": subject},
            "Body": {
                "Text": {"Data": text_body},
            },
        }
    }
    if html_body.strip():
        content["Simple"]["Body"]["Html"] = {"Data": html_body}

    request: dict[str, Any] = {
        "FromEmailAddress": sender,
        "Destination": destination,
        "Content": content,
    }
    reply_to = config.APP_AUTH_EMAIL_REPLY_TO_ADDRESS
    if reply_to:
        request["ReplyToAddresses"] = [reply_to]

    try:
        _ses.send_email(**request)
    except Exception as exc:
        _logger.exception(
            "Auth email delivery failed via SES.",
            extra={
                "from_address": sender,
                "to_domain": str(to_email or "").split("@")[-1].lower(),
            },
        )
        raise EmailDeliveryError("Failed to send auth email.") from exc
