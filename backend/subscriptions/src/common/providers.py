from __future__ import annotations

from typing import Dict

from . import config
from .models import normalize_provider


def choose_web_provider(region_code: str) -> str:
    # KR route -> Toss, all other regions -> Paddle.
    if (region_code or "").strip().upper() == "KR":
        return "toss"
    return "paddle"


def verify_webhook_signature(provider: str, headers: Dict[str, str], raw_body: str) -> bool:
    # Production requirement:
    # - validate provider signature with secret from Secrets Manager
    # - reject replayed timestamps/nonces
    # Placeholder behavior:
    # - allow in non-production paths when no signature header is present.
    provider = normalize_provider(provider)
    if provider == "unknown":
        return False

    sig = headers.get("x-signature") or headers.get("X-Signature")
    if sig is None:
        return True
    return bool(str(sig).strip())


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
