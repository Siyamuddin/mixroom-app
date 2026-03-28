from __future__ import annotations

import hashlib
import hmac
import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, Optional

import jwt
from google.auth.transport.requests import Request
from google.oauth2 import id_token as google_id_token

from . import config
from .native_auth import (
    AppUserAuthError,
    issue_session,
    upsert_social_account,
)
from .repository import BillingRepository
from .secrets import load_social_auth_secret

_repo = BillingRepository()
_google_request = Request()
_apple_jwks_cache: tuple[float, Dict[str, Any]] | None = None


@dataclass(frozen=True)
class SocialIdentity:
    provider: str
    subject: str
    email: str
    email_verified: bool
    display_name: str


class SocialAuthError(AppUserAuthError):
    pass


def complete_social_sign_in(
    provider: str,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    identity = _verify_social_identity(provider, payload)

    try:
        result = upsert_social_account(
            _repo,
            provider=identity.provider,
            subject=identity.subject,
            email=identity.email,
            email_verified=identity.email_verified,
            display_name=identity.display_name,
        )
        session = issue_session(
            _repo,
            account=result["account"],
            profile=result["profile"],
        )
        session["requiresSignupCompletion"] = bool(
            result.get("requiresSignupCompletion")
        )
        return session
    except AppUserAuthError as exc:
        raise SocialAuthError(
            exc.message,
            code=exc.code,
            status_code=exc.status_code,
            details=exc.details,
        ) from exc


def verify_social_reauthentication(
    repo: BillingRepository,
    *,
    user_id: str,
    payload: Dict[str, Any],
) -> SocialIdentity:
    safe_user_id = str(user_id or "").strip()
    if not safe_user_id:
        raise SocialAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )

    account = repo.get_auth_account(safe_user_id)
    if not account:
        raise SocialAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )

    provider = str(account.get("auth_provider") or "").strip().lower()
    if provider not in ("google", "apple", "kakao"):
        raise SocialAuthError(
            "Password re-authentication is required for this account.",
            code="DELETE_PASSWORD_REQUIRED",
            status_code=400,
            details={"provider": provider or "email"},
        )

    identity = _verify_social_identity(provider, payload)
    linked_account = repo.get_customer_link(provider, _social_link_key(identity.subject))
    if str((linked_account or {}).get("user_id") or "").strip() != safe_user_id:
        raise SocialAuthError(
            f"{_provider_label(provider)} re-authentication did not match this Mixroom account.",
            code="SOCIAL_REAUTH_MISMATCH",
            status_code=403,
            details={"provider": provider},
        )
    return identity


def _verify_social_identity(provider: str, payload: Dict[str, Any]) -> SocialIdentity:
    normalized_provider = str(provider or "").strip().lower()
    if normalized_provider == "google":
        return _verify_google_identity(payload)
    if normalized_provider == "apple":
        return _verify_apple_identity(payload)
    if normalized_provider == "kakao":
        return _verify_kakao_identity(payload)
    raise SocialAuthError(
        "Unsupported social provider.",
        code="UNSUPPORTED_SOCIAL_PROVIDER",
        status_code=400,
    )


def _verify_google_identity(payload: Dict[str, Any]) -> SocialIdentity:
    token = str(payload.get("id_token") or "").strip()
    if not token:
        raise ValueError("Google sign-in did not return an ID token.")
    if not config.GOOGLE_OAUTH_CLIENT_IDS:
        raise ValueError("Google sign-in is not configured on the backend.")

    try:
        claims = google_id_token.verify_oauth2_token(
            token,
            _google_request,
            audience=None,
        )
    except Exception as exc:
        raise ValueError("Google sign-in token is invalid.") from exc

    audience = str(claims.get("aud") or "").strip()
    authorized_party = str(claims.get("azp") or "").strip()
    allowed_client_ids = set(config.GOOGLE_OAUTH_CLIENT_IDS)
    if audience not in allowed_client_ids and authorized_party not in allowed_client_ids:
        raise ValueError("Google sign-in token audience is not allowed.")

    subject = str(claims.get("sub") or "").strip()
    email = str(claims.get("email") or "").strip().lower()
    email_verified = bool(claims.get("email_verified"))
    display_name = str(claims.get("name") or payload.get("display_name") or "").strip()
    if not subject:
        raise ValueError("Google sign-in token is missing a subject.")
    if not email or not email_verified:
        raise ValueError("Google sign-in requires a verified email address.")

    return SocialIdentity(
        provider="google",
        subject=subject,
        email=email,
        email_verified=email_verified,
        display_name=display_name,
    )


def _verify_apple_identity(payload: Dict[str, Any]) -> SocialIdentity:
    token = str(payload.get("id_token") or "").strip()
    if not token:
        raise ValueError("Apple sign-in did not return an identity token.")
    allowed_audiences = _allowed_apple_audiences()
    if not allowed_audiences:
        raise ValueError("Apple sign-in is not configured on the backend.")

    try:
        header = jwt.get_unverified_header(token)
        key_id = str(header.get("kid") or "").strip()
        if not key_id:
            raise ValueError("Apple sign-in token is missing a key ID.")
        signing_key = _apple_signing_key(key_id)
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            audience=allowed_audiences,
            issuer="https://appleid.apple.com",
        )
    except jwt.InvalidAudienceError as exc:
        raise ValueError("Apple sign-in token audience is not allowed.") from exc
    except Exception as exc:
        raise ValueError("Apple sign-in token is invalid.") from exc

    expected_nonce = str(payload.get("nonce") or "").strip()
    if expected_nonce:
        token_nonce = str(claims.get("nonce") or "").strip()
        if not token_nonce:
            raise ValueError("Apple sign-in token nonce is missing.")
        if token_nonce not in (expected_nonce, _sha256_hex(expected_nonce)):
            raise ValueError("Apple sign-in token nonce is invalid.")

    subject = str(claims.get("sub") or "").strip()
    email = str(claims.get("email") or payload.get("email") or "").strip().lower()
    email_verified = _bool_claim(claims.get("email_verified"))
    display_name = str(payload.get("display_name") or "").strip()
    if not subject:
        raise ValueError("Apple sign-in token is missing a subject.")

    return SocialIdentity(
        provider="apple",
        subject=subject,
        email=email,
        email_verified=email_verified or not email,
        display_name=display_name,
    )


def _sha256_hex(value: str) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()


def _allowed_apple_audiences() -> tuple[str, ...]:
    return tuple(
        value.strip()
        for value in str(config.APPLE_BUNDLE_ID or "").split(",")
        if value.strip()
    )


def _verify_kakao_identity(payload: Dict[str, Any]) -> SocialIdentity:
    access_token = str(payload.get("access_token") or "").strip()
    if not access_token:
        raise ValueError("Kakao sign-in did not return an access token.")

    request = urllib.request.Request(
        "https://kapi.kakao.com/v2/user/me",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise ValueError("Kakao sign-in token is invalid.") from exc
    except urllib.error.URLError as exc:
        raise ValueError("Kakao sign-in could not reach Kakao.") from exc

    try:
        claims = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise ValueError("Kakao sign-in response was invalid.") from exc

    subject = str(claims.get("id") or "").strip()
    account = claims.get("kakao_account") or {}
    if not isinstance(account, dict):
        account = {}
    profile = account.get("profile") or {}
    if not isinstance(profile, dict):
        profile = {}

    email = str(account.get("email") or "").strip().lower()
    email_verified = bool(account.get("is_email_verified"))
    display_name = str(profile.get("nickname") or payload.get("display_name") or "").strip()
    if not subject:
        raise ValueError("Kakao sign-in response is missing a user id.")
    if not email or not email_verified:
        raise ValueError("Kakao sign-in requires an account with a verified email address.")

    return SocialIdentity(
        provider="kakao",
        subject=subject,
        email=email,
        email_verified=email_verified,
        display_name=display_name,
    )


def _social_username(provider: str, subject: str) -> str:
    digest = hashlib.sha256(f"{provider}:{subject}".encode("utf-8")).hexdigest()
    return f"social_{provider}_{digest[:28]}"


def _social_password(provider: str, subject: str) -> str:
    secret = load_social_auth_secret().encode("utf-8")
    raw = hmac.new(
        secret,
        f"{provider}:{subject}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"Mx!{raw[:20]}aA9#"


def _bool_claim(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() == "true"


def _provider_label(provider: str) -> str:
    normalized = str(provider or "").strip().lower()
    if normalized == "google":
        return "Google"
    if normalized == "apple":
        return "Apple"
    if normalized == "kakao":
        return "KakaoTalk"
    return "Social"


def _social_link_key(subject: str) -> str:
    return f"auth:{str(subject or '').strip()}"


def _apple_signing_key(key_id: str) -> Any:
    import time

    global _apple_jwks_cache
    now = time.time()
    if _apple_jwks_cache is None or now - _apple_jwks_cache[0] >= 300:
        with urllib.request.urlopen("https://appleid.apple.com/auth/keys", timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
        _apple_jwks_cache = (now, payload if isinstance(payload, dict) else {})

    jwks = (_apple_jwks_cache or (0, {}))[1]
    keys = jwks.get("keys") or []
    for candidate in keys:
        if str(candidate.get("kid") or "").strip() != key_id:
            continue
        return jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(candidate))
    raise ValueError("Apple signing key not found.")
