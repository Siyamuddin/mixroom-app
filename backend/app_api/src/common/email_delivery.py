from __future__ import annotations

import logging
from typing import Any

import boto3

from . import config

_ses = boto3.client("sesv2")
_logger = logging.getLogger(__name__)


class EmailDeliveryError(RuntimeError):
    pass


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
