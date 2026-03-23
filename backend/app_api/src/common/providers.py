from __future__ import annotations

import hashlib
import hmac
from typing import Dict

from . import config
from .models import normalize_provider
from .secrets import load_webhook_secret


def choose_web_provider(region_code: str) -> str:
    # KR route -> Toss, all other regions -> Paddle.
    if (region_code or "").strip().upper() == "KR":
        return "toss"
    return "paddle"


def verify_webhook_signature(provider: str, headers: Dict[str, str], raw_body: str) -> bool:
    provider = normalize_provider(provider)
    if provider == "unknown":
        return False

    if provider == "paddle":
        if not config.PADDLE_WEBHOOK_SECRET_ARN:
            return False
        signature = str(headers.get("Paddle-Signature") or headers.get("paddle-signature") or "").strip()
        if not signature:
            return False
        secret = load_webhook_secret(config.PADDLE_WEBHOOK_SECRET_ARN)
        expected = hmac.new(
            secret.encode("utf-8"),
            (raw_body or "").encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    if provider == "toss":
        if not config.TOSS_WEBHOOK_SECRET_ARN:
            return False
        signature = str(headers.get("X-Signature") or headers.get("x-signature") or "").strip()
        if not signature:
            return False
        secret = load_webhook_secret(config.TOSS_WEBHOOK_SECRET_ARN)
        expected = hmac.new(
            secret.encode("utf-8"),
            (raw_body or "").encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    return False


def checkout_url(provider: str, session_id: str) -> str:
    base = config.DEFAULT_CHECKOUT_URL.rstrip("/")
    return f"{base}/{provider}/{session_id}"


def portal_url(provider: str) -> str:
    provider = normalize_provider(provider)
    if provider == "apple":
        return "https://apps.apple.com/account/subscriptions"
    if provider == "google":
        return "https://play.google.com/store/account/subscriptions"
    if provider == "paddle":
        return "https://customers.paddle.com"
    if provider == "toss":
        return "https://toss.im"
    return "https://www.mixroom.ai/account/subscription"
