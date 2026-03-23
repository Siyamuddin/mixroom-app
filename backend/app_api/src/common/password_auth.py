from __future__ import annotations

from typing import Any, Dict, Optional

from .native_auth import (
    AppUserAuthError,
    complete_password_sign_in as _complete_password_sign_in,
    resolve_account_by_identifier as _resolve_account_by_identifier,
)
from .repository import BillingRepository

_repo = BillingRepository()


class PasswordAuthError(AppUserAuthError):
    pass


def complete_password_sign_in(
    identifier: str,
    password: str,
) -> Dict[str, Any]:
    try:
        return _complete_password_sign_in(
            _repo,
            identifier=identifier,
            password=password,
        )
    except AppUserAuthError as exc:
        raise PasswordAuthError(
            exc.message,
            code=exc.code,
            status_code=exc.status_code,
            details=exc.details,
        ) from exc


def _resolve_cognito_user(identifier: str) -> Optional[Dict[str, Any]]:
    resolved = _resolve_account_by_identifier(_repo, identifier)
    if not resolved:
        return None
    account = resolved["account"]
    profile = resolved["profile"]
    return {
        "account": account,
        "profile": profile,
        "user": {
            "Username": str(account.get("email") or account.get("user_id") or "").strip(),
            "UserAttributes": [
                {"Name": "sub", "Value": str(account.get("user_id") or "").strip()},
                {"Name": "email", "Value": str(account.get("email") or "").strip().lower()},
                {
                    "Name": "email_verified",
                    "Value": "true" if bool(account.get("email_verified")) else "false",
                },
                {
                    "Name": "name",
                    "Value": str(profile.get("display_name") or "").strip(),
                },
            ],
        },
    }
