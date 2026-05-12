from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from . import config
from .app_auth_tokens import (
    AppAuthTokenError,
    mint_token,
    new_refresh_token,
    parse_refresh_token,
)
from .cognito_legacy_auth import (
    CognitoLegacyAuthError,
    confirm_password_reset as confirm_legacy_cognito_password_reset,
    confirm_sign_up as confirm_legacy_cognito_sign_up,
    find_user_by_email as find_legacy_cognito_user_by_email,
    refresh_session as refresh_legacy_cognito_session,
    request_password_reset as request_legacy_cognito_password_reset,
    resend_confirmation_code as resend_legacy_cognito_confirmation_code,
    sign_in_with_password as sign_in_legacy_cognito_password,
    verify_cognito_token,
)
from .email_delivery import EmailDeliveryError, EmailSuppressedError, send_auth_email
from .repository import BillingRepository
from .models import free_entitlement
from .users import (
    apply_user_profile_patch,
    build_user_profile_from_claims,
    normalize_username,
    validate_username,
)


class AppUserAuthError(ValueError):
    def __init__(
        self,
        message: str,
        *,
        code: str,
        status_code: int = 400,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code
        self.details = details or {}


def _validate_password_policy(password: str) -> None:
    issues = _password_policy_issues(password)
    if not issues:
        return
    raise AppUserAuthError(
        issues[0],
        code="WEAK_PASSWORD",
        status_code=400,
        details={"issues": issues},
    )


def register_email_account(
    repo: BillingRepository,
    *,
    email: str,
    password: str,
    display_name: str = "",
    given_name: str = "",
    family_name: str = "",
    birthdate: str = "",
    locale: str = "",
) -> Dict[str, Any]:
    safe_email = _normalize_email(email)
    if not safe_email or not password:
        raise AppUserAuthError(
            "Email and password are required.",
            code="INVALID_REQUEST",
            status_code=400,
        )
    _validate_password_policy(password)

    account = repo.get_auth_account_by_email(safe_email)
    legacy_user = find_legacy_cognito_user_by_email(safe_email)
    now = _utc_now_iso()
    created_new = False
    previous_account = dict(account) if account else None
    if account:
        provider = str(account.get("auth_provider") or "email").strip().lower() or "email"
        if provider != "email":
            raise _auth_method_conflict(
                email=safe_email,
                existing_provider=provider,
                verification_required=False,
            )
        if bool(account.get("email_verified")):
            raise AppUserAuthError(
                "An account with this email already exists.",
                code="ACCOUNT_ALREADY_EXISTS",
                status_code=409,
            )
        user_id = str(account.get("user_id") or "").strip()
        if not user_id:
            raise AppUserAuthError(
                "Existing account is invalid.",
                code="ACCOUNT_STATE_INVALID",
                status_code=500,
            )
    elif legacy_user:
        legacy_provider = _provider_from_claims(legacy_user)
        if legacy_provider != "email" or _claim_bool(legacy_user, "email_verified"):
            raise _auth_method_conflict(
                email=safe_email,
                existing_provider=legacy_provider,
                verification_required=not _claim_bool(legacy_user, "email_verified"),
            )
        user_id = str(legacy_user.get("sub") or "").strip()
        if not user_id:
            raise AppUserAuthError(
                "Existing legacy account is invalid.",
                code="ACCOUNT_STATE_INVALID",
                status_code=500,
            )
        account = {
            "user_id": user_id,
            "created_at": str(legacy_user.get("created_at") or now).strip() or now,
            "legacy_cognito_enabled": True,
        }
        created_new = True
    else:
        user_id = _new_user_id()
        account = {
            "user_id": user_id,
            "created_at": now,
        }
        created_new = True
    previous_profile = repo.get_user_profile(user_id) or None
    previous_entitlement = repo.get_entitlement(user_id) or None

    password_salt = secrets.token_hex(16)
    password_hash = _hash_password(password=password, salt=password_salt)
    verification_code = _generate_numeric_code()
    account.update(
        {
            "user_id": user_id,
            "email": safe_email,
            "email_lc": safe_email,
            "auth_provider": "email",
            "email_verified": False,
            "password_salt": password_salt,
            "password_hash": password_hash,
            "password_iterations": 210000,
            "verification_code_hash": _hash_value(verification_code),
            "verification_expires_at": _future_iso(minutes=20),
            "verification_sent_at": now,
            "password_reset_code_hash": "",
            "password_reset_expires_at": "",
            "updated_at": now,
        }
    )
    try:
        repo.put_auth_account(account)
        _upsert_user_profile(
            repo,
            account,
            display_name=display_name,
            given_name=given_name,
            family_name=family_name,
            birthdate=birthdate,
        )
        _ensure_default_entitlement(repo, user_id=user_id)
        _send_verification_email(
            email=safe_email,
            code=verification_code,
            display_name=display_name or given_name,
            locale=locale,
        )
    except Exception:
        _restore_signup_bootstrap_state(
            repo,
            user_id=user_id,
            previous_account=previous_account,
            previous_profile=previous_profile,
            previous_entitlement=previous_entitlement,
        )
        raise

    profile = repo.get_user_profile(user_id) or {}
    return {
        "user": _build_user_payload(account, profile=profile),
        "codeSent": True,
        "created": created_new,
    }


def confirm_email_account(
    repo: BillingRepository,
    *,
    email: str,
    code: str,
    password: str = "",
) -> Dict[str, Any]:
    safe_email = _normalize_email(email)
    account = repo.get_auth_account_by_email(safe_email)
    if account:
        if bool(account.get("email_verified")):
            profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
            provider = str(account.get("auth_provider") or "").strip().lower() or "email"
            if provider != "email":
                raise _auth_method_conflict(
                    email=safe_email,
                    existing_provider=provider,
                    verification_required=False,
                )
            if password.strip():
                try:
                    return complete_password_sign_in(
                        repo,
                        identifier=safe_email,
                        password=password,
                    )
                except AppUserAuthError as exc:
                    if exc.code != "INVALID_CREDENTIALS":
                        raise
            raise AppUserAuthError(
                "This email is already verified. Sign in instead.",
                code="ACCOUNT_ALREADY_VERIFIED",
                status_code=409,
                details={
                    "email": safe_email,
                    "existing_provider": "email",
                    "existing_provider_label": "Email",
                    "suggested_action": "sign_in",
                },
            )

        if not _code_matches(account.get("verification_code_hash"), code):
            raise AppUserAuthError(
                "Invalid or expired verification code.",
                code="INVALID_VERIFICATION_CODE",
                status_code=400,
            )
        if _is_expired(account.get("verification_expires_at")):
            raise AppUserAuthError(
                "Invalid or expired verification code.",
                code="INVALID_VERIFICATION_CODE",
                status_code=400,
            )

        account["email_verified"] = True
        account["verification_code_hash"] = ""
        account["verification_expires_at"] = ""
        account["updated_at"] = _utc_now_iso()
        repo.put_auth_account(account)
        _upsert_user_profile(repo, account, email_verified=True)
        profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
        return issue_session(repo, account=account, profile=profile)

    legacy_user = find_legacy_cognito_user_by_email(safe_email)
    if not legacy_user:
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    try:
        confirm_legacy_cognito_sign_up(email=safe_email, code=code)
    except CognitoLegacyAuthError as exc:
        raise _native_error_from_legacy_cognito(exc) from exc
    if not password.strip():
        raise AppUserAuthError(
            "Password is required so Mixroom can finish signing you in after verification.",
            code="PASSWORD_REQUIRED_FOR_SESSION_UPGRADE",
            status_code=400,
        )
    return complete_password_sign_in(
        repo,
        identifier=safe_email,
        password=password,
    )


def resend_email_verification_code(
    repo: BillingRepository,
    *,
    email: str = "",
    user_id: str = "",
    locale: str = "",
) -> Dict[str, Any]:
    account = None
    if user_id.strip():
        account = repo.get_auth_account(user_id.strip())
    elif email.strip():
        account = repo.get_auth_account_by_email(_normalize_email(email))
    if not account:
        safe_email = _normalize_email(email)
        legacy_user = find_legacy_cognito_user_by_email(safe_email)
        if not legacy_user:
            raise AppUserAuthError(
                "Account not found.",
                code="ACCOUNT_NOT_FOUND",
                status_code=404,
            )
        try:
            resend_legacy_cognito_confirmation_code(email=safe_email)
        except CognitoLegacyAuthError as exc:
            raise _native_error_from_legacy_cognito(exc) from exc
        return {"resent": True}
    if str(account.get("auth_provider") or "").strip().lower() != "email":
        raise AppUserAuthError(
            "This account uses social sign-in.",
            code="EMAIL_VERIFICATION_UNAVAILABLE",
            status_code=400,
        )
    if bool(account.get("email_verified")):
        return {"resent": False}

    previous_account = dict(account)
    verification_code = _generate_numeric_code()
    account["verification_code_hash"] = _hash_value(verification_code)
    account["verification_expires_at"] = _future_iso(minutes=20)
    account["verification_sent_at"] = _utc_now_iso()
    account["updated_at"] = _utc_now_iso()
    try:
        repo.put_auth_account(account)
        profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
        _send_verification_email(
            email=str(account.get("email") or "").strip().lower(),
            code=verification_code,
            display_name=str(profile.get("display_name") or "").strip(),
            locale=locale,
        )
    except Exception:
        repo.put_auth_account(previous_account)
        raise
    return {"resent": True}


def complete_password_sign_in(
    repo: BillingRepository,
    *,
    identifier: str,
    password: str,
) -> Dict[str, Any]:
    safe_identifier = str(identifier or "").strip()
    safe_password = str(password or "")
    identifier_is_email = _looks_like_email(safe_identifier)
    if not safe_identifier or not safe_password:
        raise AppUserAuthError(
            "Identifier and password are required.",
            code="INVALID_REQUEST",
            status_code=400,
        )

    resolved = resolve_account_by_identifier(repo, safe_identifier)
    legacy_identifier = safe_identifier
    if resolved is not None:
        account = resolved["account"]
        profile = resolved["profile"]
        provider = str(account.get("auth_provider") or "").strip().lower()
        if provider != "email":
            raise AppUserAuthError(
                "Password sign-in is not available for this account.",
                code="PASSWORD_SIGN_IN_UNAVAILABLE",
                status_code=409,
                details={
                    "provider": provider,
                },
            )

        if _verify_password(
            password=safe_password,
            salt=str(account.get("password_salt") or ""),
            expected_hash=str(account.get("password_hash") or ""),
        ):
            if not bool(account.get("email_verified")):
                raise _email_confirmation_required(account, profile=profile)
            return issue_session(repo, account=account, profile=profile)

        if not _can_attempt_legacy_cognito_password_sign_in(account):
            raise _invalid_credentials()
        # Legacy Cognito accepts a separate internal USERNAME. When signing in
        # via app username, force fallback auth to use the account email so
        # arbitrary legacy usernames cannot be used as login identifiers.
        legacy_identifier = str(account.get("email") or "").strip().lower() or safe_identifier
    elif not identifier_is_email:
        raise _invalid_credentials()

    try:
        legacy_claims = sign_in_legacy_cognito_password(
            identifier=legacy_identifier,
            password=safe_password,
        )
    except CognitoLegacyAuthError as exc:
        if exc.code == "UserNotConfirmedException":
            legacy_user = (
                find_legacy_cognito_user_by_email(legacy_identifier)
                if _looks_like_email(legacy_identifier)
                else None
            )
            if legacy_user:
                migrated = _migrate_legacy_cognito_account(
                    repo,
                    claims=legacy_user,
                    password="",
                    allow_passwordless_email=True,
                )
                raise _email_confirmation_required(
                    migrated["account"],
                    profile=migrated["profile"],
                ) from exc
            raise AppUserAuthError(
                exc.message,
                code="EMAIL_CONFIRMATION_REQUIRED",
                status_code=403,
            ) from exc
        if exc.code in ("NotAuthorizedException", "UserNotFoundException"):
            raise _invalid_credentials() from exc
        raise _native_error_from_legacy_cognito(exc) from exc

    migrated = _migrate_legacy_cognito_account(
        repo,
        claims=legacy_claims,
        password=safe_password,
    )
    account = migrated["account"]
    profile = migrated["profile"]
    if str(account.get("auth_provider") or "").strip().lower() != "email":
        raise AppUserAuthError(
            "Password sign-in is not available for this account.",
            code="PASSWORD_SIGN_IN_UNAVAILABLE",
            status_code=409,
            details={"provider": str(account.get("auth_provider") or "").strip().lower()},
        )
    if not bool(account.get("email_verified")):
        raise _email_confirmation_required(account, profile=profile)
    return issue_session(repo, account=account, profile=profile)


def request_password_reset(
    repo: BillingRepository,
    *,
    email: str,
    locale: str = "",
) -> Dict[str, Any]:
    safe_email = _normalize_email(email)
    if not safe_email:
        raise AppUserAuthError(
            "Email is required.",
            code="INVALID_REQUEST",
            status_code=400,
        )
    account = repo.get_auth_account_by_email(safe_email)
    if not account:
        legacy_user = find_legacy_cognito_user_by_email(safe_email)
        if not legacy_user:
            return {"sent": True}
        if _provider_from_claims(legacy_user) != "email":
            raise AppUserAuthError(
                "Password reset is not available for this account. Try signing in with the original social provider instead.",
                code="PASSWORD_RESET_UNAVAILABLE",
                status_code=409,
                details={"provider": _provider_from_claims(legacy_user)},
            )
        try:
            request_legacy_cognito_password_reset(email=safe_email)
        except CognitoLegacyAuthError as exc:
            raise _native_error_from_legacy_cognito(exc) from exc
        return {"sent": True}

    provider = str(account.get("auth_provider") or "").strip().lower() or "email"
    if provider != "email":
        raise AppUserAuthError(
            "Password reset is not available for this account. Try signing in with the original social provider instead.",
            code="PASSWORD_RESET_UNAVAILABLE",
            status_code=409,
            details={"provider": provider},
        )
    if _can_attempt_legacy_cognito_email_flow(account):
        try:
            request_legacy_cognito_password_reset(email=safe_email)
        except CognitoLegacyAuthError as exc:
            raise _native_error_from_legacy_cognito(exc) from exc
        return {"sent": True}

    previous_account = dict(account)
    reset_code = _generate_numeric_code()
    account["password_reset_code_hash"] = _hash_value(reset_code)
    account["password_reset_expires_at"] = _future_iso(minutes=20)
    account["password_reset_sent_at"] = _utc_now_iso()
    account["updated_at"] = _utc_now_iso()
    try:
        repo.put_auth_account(account)
        profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
        _send_password_reset_email(
            email=safe_email,
            code=reset_code,
            display_name=str(profile.get("display_name") or "").strip(),
            locale=locale,
        )
    except Exception:
        repo.put_auth_account(previous_account)
        raise
    return {"sent": True}


def confirm_password_reset(
    repo: BillingRepository,
    *,
    email: str,
    code: str,
    new_password: str,
) -> Dict[str, Any]:
    safe_email = _normalize_email(email)
    _validate_password_policy(new_password)
    account = repo.get_auth_account_by_email(safe_email)
    if not account or _can_attempt_legacy_cognito_email_flow(account):
        try:
            confirm_legacy_cognito_password_reset(
                email=safe_email,
                code=code,
                new_password=new_password,
            )
        except CognitoLegacyAuthError as exc:
            raise _native_error_from_legacy_cognito(exc) from exc
        legacy_user = find_legacy_cognito_user_by_email(safe_email)
        if legacy_user:
            migrated = _migrate_legacy_cognito_account(
                repo,
                claims=legacy_user,
                password=new_password,
            )
            repo.delete_auth_sessions_for_user(str(migrated["account"].get("user_id") or "").strip())
        return {"reset": True}

    account = _require_email_account(repo, email=safe_email)
    if not _code_matches(account.get("password_reset_code_hash"), code):
        raise AppUserAuthError(
            "Invalid or expired verification code.",
            code="INVALID_RESET_CODE",
            status_code=400,
        )
    if _is_expired(account.get("password_reset_expires_at")):
        raise AppUserAuthError(
            "Invalid or expired verification code.",
            code="INVALID_RESET_CODE",
            status_code=400,
        )

    password_salt = secrets.token_hex(16)
    account["password_salt"] = password_salt
    account["password_hash"] = _hash_password(password=new_password, salt=password_salt)
    account["password_iterations"] = 210000
    account["password_reset_code_hash"] = ""
    account["password_reset_expires_at"] = ""
    account["updated_at"] = _utc_now_iso()
    repo.put_auth_account(account)
    repo.delete_auth_sessions_for_user(str(account.get("user_id") or "").strip())
    return {"reset": True}


def change_password(
    repo: BillingRepository,
    *,
    user_id: str,
    current_password: str,
    new_password: str,
) -> Dict[str, Any]:
    account = repo.get_auth_account(user_id)
    if not account:
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    provider = str(account.get("auth_provider") or "").strip().lower()
    if provider != "email":
        raise AppUserAuthError(
            "Password sign-in is not available for this account.",
            code="PASSWORD_SIGN_IN_UNAVAILABLE",
            status_code=409,
            details={"provider": provider},
        )
    if not _verify_password(
        password=current_password,
        salt=str(account.get("password_salt") or ""),
        expected_hash=str(account.get("password_hash") or ""),
    ):
        raise AppUserAuthError(
            "Current password is incorrect.",
            code="INVALID_CURRENT_PASSWORD",
            status_code=400,
        )
    _validate_password_policy(new_password)
    password_salt = secrets.token_hex(16)
    account["password_salt"] = password_salt
    account["password_hash"] = _hash_password(password=new_password, salt=password_salt)
    account["password_iterations"] = 210000
    account["updated_at"] = _utc_now_iso()
    repo.put_auth_account(account)
    repo.delete_auth_sessions_for_user(user_id)
    return {"changed": True}


def verify_current_password(
    repo: BillingRepository,
    *,
    user_id: str,
    current_password: str,
) -> Dict[str, Any]:
    account = repo.get_auth_account(user_id)
    if not account:
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    provider = str(account.get("auth_provider") or "").strip().lower()
    if provider != "email":
        raise AppUserAuthError(
            "Password sign-in is not available for this account.",
            code="PASSWORD_SIGN_IN_UNAVAILABLE",
            status_code=409,
            details={"provider": provider},
        )
    if not _verify_password(
        password=current_password,
        salt=str(account.get("password_salt") or ""),
        expected_hash=str(account.get("password_hash") or ""),
    ):
        raise AppUserAuthError(
            "Current password is incorrect.",
            code="INVALID_CURRENT_PASSWORD",
            status_code=400,
        )
    return account


def update_account_display_name(
    repo: BillingRepository,
    *,
    user_id: str,
    display_name: str,
) -> Dict[str, Any]:
    account = repo.get_auth_account(user_id)
    if not account:
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    _upsert_user_profile(repo, account, display_name=display_name)
    profile = repo.get_user_profile(user_id) or {}
    return _build_user_payload(account, profile=profile)


def issue_session(
    repo: BillingRepository,
    *,
    account: Dict[str, Any],
    profile: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    safe_user_id = str(account.get("user_id") or "").strip()
    if not safe_user_id:
        raise AppUserAuthError(
            "Account state is invalid.",
            code="ACCOUNT_STATE_INVALID",
            status_code=500,
        )
    profile = profile or repo.get_user_profile(safe_user_id) or {}
    if not profile:
        _upsert_user_profile(repo, account)
        profile = repo.get_user_profile(safe_user_id) or {}

    refresh_token, refresh_token_hash = new_refresh_token()
    session_id, _ = parse_refresh_token(refresh_token)
    now = _utc_now_iso()
    repo.put_auth_session(
        {
            "session_id": session_id,
            "user_id": safe_user_id,
            "refresh_token_hash": refresh_token_hash,
            "provider": str(account.get("auth_provider") or "email").strip().lower() or "email",
            "created_at": now,
            "last_refreshed_at": now,
        }
    )
    tokens = _build_token_payload(
        account=account,
        profile=profile,
        session_id=session_id,
        refresh_token=refresh_token,
    )
    return {
        "tokens": tokens,
        "user": _build_user_payload(account, profile=profile),
    }


def refresh_session(
    repo: BillingRepository,
    *,
    refresh_token: str,
    fallback_token: str = "",
) -> Dict[str, Any]:
    try:
        session_id, refresh_token_hash = parse_refresh_token(refresh_token)
    except AppAuthTokenError as exc:
        return _exchange_legacy_cognito_session(
            repo,
            refresh_token=refresh_token,
            fallback_token=fallback_token,
        )

    session = repo.get_auth_session(session_id)
    if not session:
        raise AppUserAuthError(
            "Session expired. Please sign in again.",
            code="SESSION_INVALID",
            status_code=401,
        )
    if str(session.get("refresh_token_hash") or "").strip() != refresh_token_hash:
        raise AppUserAuthError(
            "Session expired. Please sign in again.",
            code="SESSION_INVALID",
            status_code=401,
        )
    user_id = str(session.get("user_id") or "").strip()
    account = repo.get_auth_account(user_id)
    if not account:
        repo.delete_auth_session(session_id)
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    profile = repo.get_user_profile(user_id) or {}

    repo.put_auth_session(
        {
            "session_id": session_id,
            "user_id": user_id,
            "refresh_token_hash": refresh_token_hash,
            "provider": str(account.get("auth_provider") or "email").strip().lower() or "email",
            "created_at": str(session.get("created_at") or "").strip() or _utc_now_iso(),
            "last_refreshed_at": _utc_now_iso(),
        }
    )
    tokens = _build_token_payload(
        account=account,
        profile=profile,
        session_id=session_id,
        refresh_token=refresh_token,
    )
    return {
        "tokens": tokens,
        "user": _build_user_payload(account, profile=profile),
    }


def sign_out_session(
    repo: BillingRepository,
    *,
    session_id: str,
) -> Dict[str, Any]:
    if session_id.strip():
        repo.delete_auth_session(session_id.strip())
    return {"signedOut": True}


def resolve_account_by_identifier(
    repo: BillingRepository,
    identifier: str,
) -> Optional[Dict[str, Dict[str, Any]]]:
    safe_identifier = str(identifier or "").strip()
    if not safe_identifier:
        return None

    if _looks_like_email(safe_identifier):
        account = repo.get_auth_account_by_email(_normalize_email(safe_identifier))
        if not account:
            return None
        profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
        return {"account": account, "profile": profile}

    username = normalize_username(
        safe_identifier[1:].strip() if safe_identifier.startswith("@") else safe_identifier
    )
    if username is None or validate_username(username) is not None:
        return None
    profile = repo.get_user_profile_by_username(username)
    if not profile:
        return None
    user_id = str(profile.get("user_id") or "").strip()
    if not user_id:
        return None
    account = repo.get_auth_account(user_id)
    if not account:
        return None
    return {"account": account, "profile": profile}


def upsert_social_account(
    repo: BillingRepository,
    *,
    provider: str,
    subject: str,
    email: str,
    email_verified: bool,
    display_name: str = "",
) -> Dict[str, Any]:
    normalized_provider = str(provider or "").strip().lower()
    if normalized_provider not in ("google", "apple", "kakao"):
        raise AppUserAuthError(
            "Unsupported social provider.",
            code="UNSUPPORTED_SOCIAL_PROVIDER",
            status_code=400,
        )

    linked_account = repo.get_customer_link(normalized_provider, _social_link_key(subject))
    if linked_account:
        user_id = str(linked_account.get("user_id") or "").strip()
        account = repo.get_auth_account(user_id)
        existing_profile = repo.get_user_profile(user_id) or {}
        resolved_email = _resolve_linked_social_email(
            repo,
            user_id=user_id,
            current_email=str(
                (account or {}).get("email") or existing_profile.get("email") or ""
            ).strip().lower(),
            candidate_email=email,
        )
        if not account:
            if not user_id:
                raise AppUserAuthError(
                    "Linked account could not be loaded.",
                    code="ACCOUNT_STATE_INVALID",
                    status_code=500,
                )
            account = _build_migrated_account(
                existing={
                    "user_id": user_id,
                    "created_at": str(existing_profile.get("created_at") or _utc_now_iso()).strip()
                    or _utc_now_iso(),
                },
                claims={
                    "sub": user_id,
                    "email": resolved_email,
                    "email_verified": email_verified,
                    "provider": normalized_provider,
                    "name": display_name,
                },
                password="",
                allow_passwordless_email=True,
            )
            repo.put_auth_account(account)
        if resolved_email:
            account["email"] = resolved_email
            account["email_lc"] = resolved_email
        account["email_verified"] = bool(email_verified) or bool(account.get("email_verified"))
        account["auth_provider"] = normalized_provider
        account["updated_at"] = _utc_now_iso()
        repo.put_auth_account(account)
        _upsert_user_profile(
            repo,
            account,
            display_name=display_name,
            email_verified=bool(account.get("email_verified")),
        )
        profile = repo.get_user_profile(user_id) or {}
        return {
            "requiresSignupCompletion": False,
            "account": account,
            "profile": profile,
        }

    safe_email = _normalize_email(email)
    if not safe_email or not email_verified:
        raise AppUserAuthError(
            "This account must provide a verified email address.",
            code="SOCIAL_EMAIL_UNVERIFIED",
            status_code=400,
        )

    existing = repo.get_auth_account_by_email(safe_email)
    requires_signup_completion = False
    if existing:
        existing_provider = str(existing.get("auth_provider") or "").strip().lower() or "email"
        if existing_provider == normalized_provider:
            account = existing
        elif existing_provider == "email" and not bool(existing.get("email_verified")):
            account = dict(existing)
            account["auth_provider"] = normalized_provider
            account["email_verified"] = True
            account["password_hash"] = ""
            account["password_salt"] = ""
            account["verification_code_hash"] = ""
            account["verification_expires_at"] = ""
            requires_signup_completion = True
        else:
            raise _auth_method_conflict(
                email=safe_email,
                existing_provider=existing_provider,
                verification_required=not bool(existing.get("email_verified")),
            )
    else:
        account = _create_social_seed_account(
            repo,
            provider=normalized_provider,
            email=safe_email,
            email_verified=True,
            display_name=display_name,
        )
        requires_signup_completion = True

    account["updated_at"] = _utc_now_iso()
    repo.put_auth_account(account)
    repo.put_customer_link(
        normalized_provider,
        _social_link_key(subject),
        str(account.get("user_id") or "").strip(),
        {
            "link_type": "auth_identity",
            "auth_provider": normalized_provider,
            "email": safe_email,
            "subject": subject,
            "linked_at": _utc_now_iso(),
        },
    )
    _upsert_user_profile(
        repo,
        account,
        display_name=display_name,
        email_verified=True,
    )
    _ensure_default_entitlement(
        repo,
        user_id=str(account.get("user_id") or "").strip(),
    )
    profile = repo.get_user_profile(str(account.get("user_id") or "").strip()) or {}
    return {
        "requiresSignupCompletion": requires_signup_completion,
        "account": account,
        "profile": profile,
    }


def _exchange_legacy_cognito_session(
    repo: BillingRepository,
    *,
    refresh_token: str,
    fallback_token: str,
) -> Dict[str, Any]:
    legacy_claims = None
    safe_refresh_token = str(refresh_token or "").strip()
    safe_fallback_token = str(fallback_token or "").strip()

    if safe_refresh_token:
        try:
            legacy_claims = refresh_legacy_cognito_session(refresh_token=safe_refresh_token)
        except CognitoLegacyAuthError as exc:
            if not safe_fallback_token:
                raise AppUserAuthError(
                    "Session expired. Please sign in again.",
                    code="SESSION_INVALID",
                    status_code=401,
                ) from exc

    if legacy_claims is None and safe_fallback_token:
        try:
            legacy_claims = verify_cognito_token(safe_fallback_token)
        except CognitoLegacyAuthError as exc:
            raise AppUserAuthError(
                "Session expired. Please sign in again.",
                code="SESSION_INVALID",
                status_code=401,
            ) from exc

    if legacy_claims is None:
        raise AppUserAuthError(
            "Session expired. Please sign in again.",
            code="SESSION_INVALID",
            status_code=401,
        )

    migrated = _migrate_legacy_cognito_account(
        repo,
        claims=legacy_claims,
        password="",
        allow_passwordless_email=True,
    )
    return issue_session(
        repo,
        account=migrated["account"],
        profile=migrated["profile"],
    )


def _migrate_legacy_cognito_account(
    repo: BillingRepository,
    *,
    claims: Dict[str, Any],
    password: str,
    allow_passwordless_email: bool = False,
) -> Dict[str, Dict[str, Any]]:
    safe_user_id = str(claims.get("sub") or "").strip()
    safe_email = _normalize_email(claims.get("email") or "")
    if not safe_user_id:
        raise AppUserAuthError(
            "Legacy account could not be migrated.",
            code="ACCOUNT_STATE_INVALID",
            status_code=500,
        )

    existing = repo.get_auth_account(safe_user_id)
    existing_by_email = repo.get_auth_account_by_email(safe_email) if safe_email else None
    if existing is None and existing_by_email is not None:
        existing_email_user_id = str(existing_by_email.get("user_id") or "").strip()
        if existing_email_user_id != safe_user_id:
            raise AppUserAuthError(
                "Legacy account conflicts with an existing Mixroom account.",
                code="ACCOUNT_MIGRATION_CONFLICT",
                status_code=409,
                details={
                    "email": safe_email,
                    "existing_user_id": existing_email_user_id,
                    "legacy_user_id": safe_user_id,
                },
            )
        existing = existing_by_email

    existing_profile = repo.get_user_profile(safe_user_id) or {}
    profile_by_email = repo.get_user_profile_by_email(safe_email) if safe_email else None
    if (
        profile_by_email
        and str(profile_by_email.get("user_id") or "").strip()
        and str(profile_by_email.get("user_id") or "").strip() != safe_user_id
    ):
        raise AppUserAuthError(
            "Legacy account conflicts with an existing Mixroom profile.",
            code="ACCOUNT_MIGRATION_CONFLICT",
            status_code=409,
            details={
                "email": safe_email,
                "existing_user_id": str(profile_by_email.get("user_id") or "").strip(),
                "legacy_user_id": safe_user_id,
            },
        )
    if not existing_profile and profile_by_email:
        existing_profile = profile_by_email

    seed_existing = dict(existing or {})
    seed_existing.setdefault("user_id", safe_user_id)
    seed_existing.setdefault(
        "created_at",
        str(existing_profile.get("created_at") or _utc_now_iso()).strip() or _utc_now_iso(),
    )
    if existing_profile.get("email") and not seed_existing.get("email"):
        seed_existing["email"] = str(existing_profile.get("email") or "").strip().lower()
        seed_existing["email_lc"] = seed_existing["email"]

    account = _build_migrated_account(
        existing=seed_existing,
        claims=claims,
        password=password,
        allow_passwordless_email=allow_passwordless_email,
    )
    repo.put_auth_account(account)

    profile = build_user_profile_from_claims(claims, existing=existing_profile)
    repo.upsert_user_profile(
        profile,
        previous_username_lc=str((existing_profile or {}).get("username_lc") or "").strip().lower() or None,
    )
    _ensure_default_entitlement(repo, user_id=safe_user_id)
    return {
        "account": account,
        "profile": profile,
    }


def _build_migrated_account(
    *,
    existing: Dict[str, Any],
    claims: Dict[str, Any],
    password: str,
    allow_passwordless_email: bool,
) -> Dict[str, Any]:
    safe_user_id = str(claims.get("sub") or existing.get("user_id") or "").strip()
    safe_email = _normalize_email(claims.get("email") or existing.get("email") or "")
    provider = _provider_from_claims(claims)
    if provider == "email" and not safe_email:
        raise AppUserAuthError(
            "Legacy email account is missing an email address.",
            code="ACCOUNT_STATE_INVALID",
            status_code=500,
        )

    account = dict(existing)
    account.update(
        {
            "user_id": safe_user_id,
            "created_at": str(existing.get("created_at") or _utc_now_iso()).strip() or _utc_now_iso(),
            "updated_at": _utc_now_iso(),
            "auth_provider": provider,
            "email": safe_email,
            "email_lc": safe_email,
            "email_verified": _claim_bool(claims, "email_verified") or bool(existing.get("email_verified")),
            "legacy_cognito_enabled": provider == "email" and not password.strip(),
            "legacy_cognito_username": str(
                claims.get("cognito:username") or existing.get("legacy_cognito_username") or safe_email
            ).strip(),
            "legacy_cognito_migrated_at": _utc_now_iso(),
        }
    )
    if provider != "email":
        account["password_hash"] = ""
        account["password_salt"] = ""
    elif password.strip():
        password_salt = secrets.token_hex(16)
        account["password_salt"] = password_salt
        account["password_hash"] = _hash_password(password=password, salt=password_salt)
        account["password_iterations"] = 210000
        account["legacy_cognito_enabled"] = False
    elif not allow_passwordless_email and not str(account.get("password_hash") or "").strip():
        raise AppUserAuthError(
            "Password is required to finish migrating this account.",
            code="PASSWORD_REQUIRED_FOR_SESSION_UPGRADE",
            status_code=400,
        )
    account.setdefault("verification_code_hash", "")
    account.setdefault("verification_expires_at", "")
    account.setdefault("password_reset_code_hash", "")
    account.setdefault("password_reset_expires_at", "")
    return account


def _create_social_seed_account(
    repo: BillingRepository,
    *,
    provider: str,
    email: str,
    email_verified: bool,
    display_name: str,
) -> Dict[str, Any]:
    existing_profile = repo.get_user_profile_by_email(email) or {}
    legacy_user = find_legacy_cognito_user_by_email(email) or {}
    existing_profile_user_id = str(existing_profile.get("user_id") or "").strip()
    legacy_user_id = str(legacy_user.get("sub") or "").strip()
    if existing_profile_user_id and legacy_user_id and existing_profile_user_id != legacy_user_id:
        raise AppUserAuthError(
            "Legacy account conflicts with an existing Mixroom profile.",
            code="ACCOUNT_MIGRATION_CONFLICT",
            status_code=409,
            details={
                "email": email,
                "existing_user_id": existing_profile_user_id,
                "legacy_user_id": legacy_user_id,
            },
        )
    user_id = existing_profile_user_id or legacy_user_id or _new_user_id()
    return _build_migrated_account(
        existing={
            "user_id": user_id,
            "created_at": str(
                existing_profile.get("created_at")
                or legacy_user.get("created_at")
                or _utc_now_iso()
            ).strip()
            or _utc_now_iso(),
        },
        claims={
            "sub": user_id,
            "email": email,
            "email_verified": email_verified,
            "provider": provider,
            "name": display_name,
            "identities": legacy_user.get("identities"),
            "cognito:username": legacy_user.get("cognito:username"),
        },
        password="",
        allow_passwordless_email=provider != "email",
    )


def _resolve_linked_social_email(
    repo: BillingRepository,
    *,
    user_id: str,
    current_email: str,
    candidate_email: str,
) -> str:
    safe_current_email = _normalize_email(current_email)
    safe_candidate_email = _normalize_email(candidate_email)
    if not safe_candidate_email or safe_candidate_email == safe_current_email:
        return safe_current_email or safe_candidate_email

    existing = repo.get_auth_account_by_email(safe_candidate_email)
    existing_user_id = str((existing or {}).get("user_id") or "").strip()
    if existing_user_id and existing_user_id != user_id:
        return safe_current_email
    return safe_candidate_email


def _can_attempt_legacy_cognito_password_sign_in(account: Dict[str, Any]) -> bool:
    return bool(
        str(account.get("legacy_cognito_enabled") or "").strip().lower() == "true"
        or account.get("legacy_cognito_enabled") is True
        or not str(account.get("password_hash") or "").strip()
    )


def _can_attempt_legacy_cognito_email_flow(account: Dict[str, Any]) -> bool:
    provider = str(account.get("auth_provider") or "").strip().lower() or "email"
    if provider != "email":
        return False
    return _can_attempt_legacy_cognito_password_sign_in(account)


def _native_error_from_legacy_cognito(exc: CognitoLegacyAuthError) -> AppUserAuthError:
    if exc.code in ("NotAuthorizedException", "UserNotFoundException"):
        return _invalid_credentials()
    if exc.code == "UserNotConfirmedException":
        return AppUserAuthError(
            exc.message,
            code="EMAIL_CONFIRMATION_REQUIRED",
            status_code=403,
        )
    if exc.code in ("CodeMismatchException", "ExpiredCodeException"):
        return AppUserAuthError(
            "Invalid or expired verification code.",
            code="INVALID_VERIFICATION_CODE",
            status_code=400,
        )
    return AppUserAuthError(
        exc.message,
        code=exc.code,
        status_code=exc.status_code,
    )


def _email_confirmation_required(
    account: Dict[str, Any],
    *,
    profile: Dict[str, Any],
) -> AppUserAuthError:
    return AppUserAuthError(
        "Email not verified yet. Verify your email to finish signing in.",
        code="EMAIL_CONFIRMATION_REQUIRED",
        status_code=403,
        details={
            "email": str(account.get("email") or "").strip().lower(),
            "pending_username": str(profile.get("username") or str(account.get("email") or "")).strip(),
        },
    )


def _claim_bool(claims: Dict[str, Any], *keys: str) -> bool:
    for key in keys:
        value = claims.get(key)
        if isinstance(value, bool):
            return value
        text = str(value or "").strip().lower()
        if text == "true":
            return True
        if text == "false":
            return False
    return False


def _provider_from_claims(claims: Dict[str, Any]) -> str:
    direct_provider = str(claims.get("provider") or claims.get("auth_provider") or "").strip().lower()
    if direct_provider in ("email", "google", "apple", "kakao"):
        return direct_provider
    raw_identities = str(claims.get("identities") or "").strip()
    if raw_identities:
        try:
            identities = json.loads(raw_identities)
            if isinstance(identities, list) and identities:
                provider_name = str((identities[0] or {}).get("providerName") or "").strip().lower()
                if provider_name == "google":
                    return "google"
                if provider_name == "signinwithapple":
                    return "apple"
                if provider_name == "kakao":
                    return "kakao"
        except Exception:
            pass
    return "email"


def _build_token_payload(
    *,
    account: Dict[str, Any],
    profile: Dict[str, Any],
    session_id: str,
    refresh_token: str,
) -> Dict[str, Any]:
    user = _build_user_payload(account, profile=profile)
    claims = {
        "sub": user["userId"],
        "email": user["email"],
        "email_verified": bool(user["emailVerified"]),
        "name": user["displayName"],
        "provider": user["provider"],
        "sid": session_id,
    }
    given_name = str(profile.get("given_name") or "").strip()
    family_name = str(profile.get("family_name") or "").strip()
    if given_name:
        claims["given_name"] = given_name
    if family_name:
        claims["family_name"] = family_name
    access_token = mint_token(claims, token_use="access")
    id_token = mint_token(claims, token_use="id")
    expires_at = datetime.now(timezone.utc) + timedelta(
        seconds=config.APP_AUTH_ACCESS_TOKEN_TTL_SECONDS
    )
    return {
        "accessToken": access_token,
        "idToken": id_token,
        "refreshToken": refresh_token,
        "expiresAtUtc": expires_at.isoformat(),
    }


def _build_user_payload(
    account: Dict[str, Any],
    *,
    profile: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    current_profile = profile or {}
    safe_email = str(account.get("email") or current_profile.get("email") or "").strip().lower()
    display_name = str(current_profile.get("display_name") or "").strip()
    if not display_name:
        display_name = _display_name_from_email(safe_email)
    created_at = (
        str(current_profile.get("created_at") or "").strip()
        or str(account.get("created_at") or "").strip()
        or _utc_now_iso()
    )
    return {
        "userId": str(account.get("user_id") or "").strip(),
        "email": safe_email,
        "displayName": display_name,
        "provider": str(account.get("auth_provider") or "email").strip().lower() or "email",
        "emailVerified": bool(account.get("email_verified")),
        "createdAt": created_at,
    }


def _upsert_user_profile(
    repo: BillingRepository,
    account: Dict[str, Any],
    *,
    display_name: str = "",
    given_name: str = "",
    family_name: str = "",
    birthdate: str = "",
    email_verified: Optional[bool] = None,
) -> Dict[str, Any]:
    safe_user_id = str(account.get("user_id") or "").strip()
    safe_email = str(account.get("email") or "").strip().lower()
    if not safe_user_id or not safe_email:
        raise AppUserAuthError(
            "Account state is invalid.",
            code="ACCOUNT_STATE_INVALID",
            status_code=500,
        )
    current = repo.get_user_profile(safe_user_id) or {}
    now = _utc_now_iso()
    base = {
        "user_id": safe_user_id,
        "email": safe_email,
        "email_lc": safe_email,
        "display_name": str(current.get("display_name") or "").strip() or _display_name_from_email(safe_email),
        "email_verified": bool(account.get("email_verified")) if email_verified is None else bool(email_verified),
        "cognito_username": str(current.get("cognito_username") or "").strip(),
        "auth_provider": str(account.get("auth_provider") or current.get("auth_provider") or "email").strip().lower() or "email",
        "username": current.get("username"),
        "username_lc": current.get("username_lc"),
        "given_name": current.get("given_name"),
        "family_name": current.get("family_name"),
        "birthdate": current.get("birthdate"),
        "avatar_url": current.get("avatar_url"),
        "bio": current.get("bio"),
        "profile_status": str(current.get("profile_status") or "active").strip() or "active",
        "onboarding_state": current.get("onboarding_state"),
        "accepted_terms_version": current.get("accepted_terms_version"),
        "accepted_privacy_version": current.get("accepted_privacy_version"),
        "accepted_at": current.get("accepted_at"),
        "newsletter_opt_in": bool(current.get("newsletter_opt_in")),
        "newsletter_opt_in_at": current.get("newsletter_opt_in_at"),
        "created_at": current.get("created_at") or now,
        "updated_at": now,
        "last_seen_at": now,
        "bootstrap_source": "native_auth",
        "schema_version": 4,
    }
    patch: Dict[str, Any] = {}
    if display_name.strip():
        patch["display_name"] = display_name.strip()
    if given_name.strip():
        patch["given_name"] = given_name.strip()
    if family_name.strip():
        patch["family_name"] = family_name.strip()
    if birthdate.strip():
        patch["birthdate"] = birthdate.strip()
    profile = apply_user_profile_patch(base, patch) if patch else base
    repo.upsert_user_profile(
        profile,
        previous_username_lc=str((current or {}).get("username_lc") or "").strip().lower() or None,
    )
    return profile


def _require_email_account(repo: BillingRepository, *, email: str) -> Dict[str, Any]:
    safe_email = _normalize_email(email)
    account = repo.get_auth_account_by_email(safe_email)
    if not account:
        raise AppUserAuthError(
            "Account not found.",
            code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    provider = str(account.get("auth_provider") or "").strip().lower() or "email"
    if provider != "email":
        raise AppUserAuthError(
            "This account uses social sign-in.",
            code="PASSWORD_RESET_UNAVAILABLE",
            status_code=409,
            details={"provider": provider},
        )
    return account


def _ensure_default_entitlement(
    repo: BillingRepository,
    *,
    user_id: str,
) -> None:
    safe_user_id = str(user_id or "").strip()
    if not safe_user_id:
        return
    if repo.get_entitlement(safe_user_id):
        return
    repo.put_entitlement(
        free_entitlement(
            user_id=safe_user_id,
        ).to_dict()
    )


def _restore_signup_bootstrap_state(
    repo: BillingRepository,
    *,
    user_id: str,
    previous_account: Optional[Dict[str, Any]],
    previous_profile: Optional[Dict[str, Any]],
    previous_entitlement: Optional[Dict[str, Any]],
) -> None:
    if previous_account is None:
        repo.delete_auth_account(user_id)
    else:
        repo.put_auth_account(previous_account)

    if previous_profile is None:
        repo.delete_user_profile(user_id)
    else:
        repo.upsert_user_profile(previous_profile)

    if previous_entitlement is None:
        repo.delete_entitlement(user_id)
    else:
        repo.put_entitlement(previous_entitlement)


def _send_verification_email(*, email: str, code: str, display_name: str, locale: str = "") -> None:
    email_locale = _auth_email_locale(locale)
    if email_locale == "ko":
        subject = "Mixroom 계정 이메일 인증"
        text_body = (
            "안녕하세요,\n\n"
            f"Mixroom 인증 코드는 {code}입니다.\n"
            "이 코드는 20분 후 만료됩니다.\n\n"
            "요청하지 않았다면 이 메일을 무시해 주세요."
        )
    else:
        subject = "Verify your Mixroom account"
        text_body = (
            "Hello,\n\n"
            f"Your Mixroom verification code is {code}.\n"
            "It expires in 20 minutes.\n\n"
            "If you did not request this, you can ignore this email."
        )
    try:
        send_auth_email(
            to_email=email,
            subject=subject,
            text_body=text_body,
        )
    except EmailSuppressedError as exc:
        details = {"reason": exc.reason} if exc.reason else None
        raise AppUserAuthError(
            "This email address cannot receive verification emails right now.",
            code="EMAIL_SUPPRESSED",
            status_code=409,
            details=details,
        ) from exc
    except EmailDeliveryError as exc:
        raise AppUserAuthError(
            "Email delivery is not configured.",
            code="EMAIL_DELIVERY_UNAVAILABLE",
            status_code=503,
        ) from exc


def _send_password_reset_email(*, email: str, code: str, display_name: str, locale: str = "") -> None:
    email_locale = _auth_email_locale(locale)
    if email_locale == "ko":
        subject = "Mixroom 비밀번호 재설정"
        text_body = (
            "안녕하세요,\n\n"
            f"Mixroom 비밀번호 재설정 코드는 {code}입니다.\n"
            "이 코드는 20분 후 만료됩니다.\n\n"
            "요청하지 않았다면 이 메일을 무시해 주세요."
        )
    else:
        subject = "Reset your Mixroom password"
        text_body = (
            "Hello,\n\n"
            f"Your Mixroom password reset code is {code}.\n"
            "It expires in 20 minutes.\n\n"
            "If you did not request this, you can ignore this email."
        )
    try:
        send_auth_email(
            to_email=email,
            subject=subject,
            text_body=text_body,
        )
    except EmailSuppressedError as exc:
        details = {"reason": exc.reason} if exc.reason else None
        raise AppUserAuthError(
            "This email address cannot receive password reset emails right now.",
            code="EMAIL_SUPPRESSED",
            status_code=409,
            details=details,
        ) from exc
    except EmailDeliveryError as exc:
        raise AppUserAuthError(
            "Email delivery is not configured.",
            code="EMAIL_DELIVERY_UNAVAILABLE",
            status_code=503,
        ) from exc


def _invalid_credentials() -> AppUserAuthError:
    return AppUserAuthError(
        "Incorrect email, username, or password.",
        code="INVALID_CREDENTIALS",
        status_code=401,
    )


def _auth_email_locale(locale: str) -> str:
    safe = str(locale or "").strip().lower()
    if not safe:
        return "en"
    return "ko" if safe.startswith("ko") else "en"


def _auth_method_conflict(
    *,
    email: str,
    existing_provider: str,
    verification_required: bool,
) -> AppUserAuthError:
    method_label = _provider_label(existing_provider)
    if verification_required:
        message = (
            f"Mixroom already has an unverified account for {email}. "
            "Verify that email first, then keep using email sign-in."
        )
        suggested_action = "verify_email"
    elif existing_provider == "email":
        message = (
            f"Mixroom already has an account for {email}. "
            "Use email sign-in for that account."
        )
        suggested_action = "use_email"
    else:
        message = (
            f"Mixroom already has an account for {email}. "
            f"Use {method_label} sign-in for that account."
        )
        suggested_action = f"use_{existing_provider}"
    return AppUserAuthError(
        message,
        code="AUTH_METHOD_CONFLICT",
        status_code=409,
        details={
            "email": email,
            "existing_provider": existing_provider,
            "existing_provider_label": method_label,
            "verification_required": verification_required,
            "password_reset_available": existing_provider == "email" and not verification_required,
            "suggested_action": suggested_action,
        },
    )


def _provider_label(provider: str) -> str:
    if provider == "google":
        return "Google"
    if provider == "apple":
        return "Apple"
    if provider == "kakao":
        return "KakaoTalk"
    return "Email"


def _social_link_key(subject: str) -> str:
    return f"auth:{str(subject or '').strip()}"


def _new_user_id() -> str:
    return f"user_{secrets.token_hex(16)}"


def _password_policy_issues(password: str) -> list[str]:
    safe_password = str(password or "").strip()
    issues: list[str] = []
    if len(safe_password) < config.AUTH_PASSWORD_MIN_LENGTH:
        issues.append(
            f"Password must be at least {config.AUTH_PASSWORD_MIN_LENGTH} characters."
        )
    if config.AUTH_PASSWORD_REQUIRE_UPPERCASE and not any(
        char.isupper() for char in safe_password
    ):
        issues.append("Password must include an uppercase letter.")
    if config.AUTH_PASSWORD_REQUIRE_LOWERCASE and not any(
        char.islower() for char in safe_password
    ):
        issues.append("Password must include a lowercase letter.")
    if config.AUTH_PASSWORD_REQUIRE_NUMBER and not any(
        char.isdigit() for char in safe_password
    ):
        issues.append("Password must include a number.")
    if config.AUTH_PASSWORD_REQUIRE_SYMBOL and not any(
        not char.isalnum() for char in safe_password
    ):
        issues.append("Password must include a symbol.")
    return issues


def _hash_password(*, password: str, salt: str) -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        210000,
    )
    return digest.hex()


def _verify_password(*, password: str, salt: str, expected_hash: str) -> bool:
    safe_expected = str(expected_hash or "").strip().lower()
    safe_salt = str(salt or "").strip()
    if not safe_expected or not safe_salt:
        return False
    actual = _hash_password(password=password, salt=safe_salt)
    return hmac.compare_digest(actual, safe_expected)


def _generate_numeric_code() -> str:
    return f"{secrets.randbelow(1000000):06d}"


def _hash_value(value: str) -> str:
    return hashlib.sha256(str(value or "").strip().encode("utf-8")).hexdigest()


def _code_matches(expected_hash: Any, candidate_code: str) -> bool:
    safe_expected = str(expected_hash or "").strip().lower()
    safe_candidate = str(candidate_code or "").strip()
    if not safe_expected or not safe_candidate:
        return False
    actual = _hash_value(safe_candidate)
    return hmac.compare_digest(actual, safe_expected)


def _normalize_email(email: str) -> str:
    return str(email or "").strip().lower()


def _looks_like_email(value: str) -> bool:
    safe = str(value or "").strip()
    return "@" in safe and "." in safe


def _future_iso(*, minutes: int = 0, seconds: int = 0) -> str:
    return (
        datetime.now(timezone.utc)
        + timedelta(minutes=minutes, seconds=seconds)
    ).isoformat()


def _iso_to_epoch_seconds(value: str) -> int:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    else:
        parsed = parsed.astimezone(timezone.utc)
    return int(parsed.timestamp())


def _is_expired(value: Any) -> bool:
    raw = str(value or "").strip()
    if not raw:
        return True
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return True
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    else:
        parsed = parsed.astimezone(timezone.utc)
    return parsed <= datetime.now(timezone.utc)


def _display_name_from_email(email: str) -> str:
    local = str(email or "").split("@")[0].strip()
    if not local:
        return "Mixroom User"
    spaced = " ".join(
        part
        for part in local.replace(".", " ").replace("_", " ").replace("-", " ").split()
        if part
    )
    if not spaced:
        return "Mixroom User"
    return " ".join(part[:1].upper() + part[1:] for part in spaced.split())


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
