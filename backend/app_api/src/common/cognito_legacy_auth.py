from __future__ import annotations

import json
import time
import urllib.request
from typing import Any, Dict, Iterable, Optional

import boto3
from botocore.exceptions import ClientError

from . import config

_jwks_cache: Dict[str, tuple[float, Dict[str, Any]]] = {}
_cognito = boto3.client("cognito-idp")


class CognitoLegacyAuthError(ValueError):
    def __init__(
        self,
        message: str,
        *,
        code: str,
        status_code: int = 400,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


def is_enabled() -> bool:
    return bool(
        config.COGNITO_REGION
        and config.COGNITO_APP_CLIENT_ID
        and config.COGNITO_USER_POOL_ID
    )


def verify_cognito_token(
    token: str,
    *,
    audiences: Iterable[str] | None = None,
    user_pool_ids: Iterable[str] | None = None,
) -> Dict[str, Any]:
    safe_token = str(token or "").strip()
    if not safe_token:
        raise CognitoLegacyAuthError(
            "Missing Cognito token.",
            code="COGNITO_TOKEN_INVALID",
            status_code=401,
        )
    if not is_enabled():
        raise CognitoLegacyAuthError(
            "Legacy Cognito auth is not configured.",
            code="COGNITO_NOT_CONFIGURED",
            status_code=503,
        )

    try:
        import jwt

        unverified = jwt.get_unverified_header(safe_token)
        kid = str(unverified.get("kid") or "").strip()
        if not kid:
            raise CognitoLegacyAuthError(
                "Cognito token key ID is missing.",
                code="COGNITO_TOKEN_INVALID",
                status_code=401,
            )

        accepted_audiences = [
            value.strip()
            for value in (audiences or [config.COGNITO_APP_CLIENT_ID])
            if str(value or "").strip()
        ]
        accepted_user_pool_ids = [
            value.strip()
            for value in (user_pool_ids or [config.COGNITO_USER_POOL_ID])
            if str(value or "").strip()
        ]

        for user_pool_id in accepted_user_pool_ids:
            jwks = _fetch_cognito_jwks(user_pool_id)
            keys = jwks.get("keys") or []
            signing_key = None
            for candidate in keys:
                if str(candidate.get("kid") or "").strip() != kid:
                    continue
                signing_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(candidate))
                break
            if signing_key is None:
                continue

            issuer = (
                f"https://cognito-idp.{config.COGNITO_REGION}.amazonaws.com/"
                f"{user_pool_id}"
            )
            try:
                payload = jwt.decode(
                    safe_token,
                    signing_key,
                    algorithms=["RS256"],
                    issuer=issuer,
                    options={"verify_aud": False},
                )
            except Exception:
                continue
            if not isinstance(payload, dict):
                continue

            token_use = str(payload.get("token_use") or "").strip()
            if token_use not in ("", "id", "access"):
                continue
            token_audiences = _extract_token_audiences(payload)
            if accepted_audiences and not any(
                audience in accepted_audiences for audience in token_audiences
            ):
                continue
            return payload
    except CognitoLegacyAuthError:
        raise
    except Exception as exc:
        raise CognitoLegacyAuthError(
            "Cognito token is invalid.",
            code="COGNITO_TOKEN_INVALID",
            status_code=401,
        ) from exc

    raise CognitoLegacyAuthError(
        "Cognito token is invalid.",
        code="COGNITO_TOKEN_INVALID",
        status_code=401,
    )


def sign_in_with_password(
    *,
    identifier: str,
    password: str,
) -> Dict[str, Any]:
    response = _initiate_auth(
        flow="USER_PASSWORD_AUTH",
        parameters={
            "USERNAME": str(identifier or "").strip(),
            "PASSWORD": str(password or ""),
        },
    )
    return _claims_from_auth_result(response)


def refresh_session(
    *,
    refresh_token: str,
) -> Dict[str, Any]:
    response = _initiate_auth(
        flow="REFRESH_TOKEN_AUTH",
        parameters={
            "REFRESH_TOKEN": str(refresh_token or "").strip(),
        },
    )
    return _claims_from_auth_result(response)


def resend_confirmation_code(
    *,
    email: str,
) -> None:
    _call_cognito(
        "resend_confirmation_code",
        ClientId=config.COGNITO_APP_CLIENT_ID,
        Username=str(email or "").strip().lower(),
    )


def confirm_sign_up(
    *,
    email: str,
    code: str,
) -> None:
    _call_cognito(
        "confirm_sign_up",
        ClientId=config.COGNITO_APP_CLIENT_ID,
        Username=str(email or "").strip().lower(),
        ConfirmationCode=str(code or "").strip(),
    )


def request_password_reset(
    *,
    email: str,
) -> None:
    _call_cognito(
        "forgot_password",
        ClientId=config.COGNITO_APP_CLIENT_ID,
        Username=str(email or "").strip().lower(),
    )


def confirm_password_reset(
    *,
    email: str,
    code: str,
    new_password: str,
) -> None:
    _call_cognito(
        "confirm_forgot_password",
        ClientId=config.COGNITO_APP_CLIENT_ID,
        Username=str(email or "").strip().lower(),
        ConfirmationCode=str(code or "").strip(),
        Password=str(new_password or ""),
    )


def find_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    safe_email = str(email or "").strip().lower()
    if not safe_email or not is_enabled():
        return None
    users = _list_users(filter_expression=f'email = "{_escape_filter_value(safe_email)}"')
    if not users:
        return None
    return _user_to_claims(users[0])


def _initiate_auth(
    *,
    flow: str,
    parameters: Dict[str, str],
) -> Dict[str, Any]:
    response = _call_cognito(
        "initiate_auth",
        ClientId=config.COGNITO_APP_CLIENT_ID,
        AuthFlow=flow,
        AuthParameters=parameters,
    )
    if not isinstance(response, dict):
        raise CognitoLegacyAuthError(
            "Legacy sign-in failed.",
            code="COGNITO_AUTH_FAILED",
            status_code=401,
        )
    return response


def _claims_from_auth_result(response: Dict[str, Any]) -> Dict[str, Any]:
    auth_result = response.get("AuthenticationResult") or {}
    if not isinstance(auth_result, dict):
        raise CognitoLegacyAuthError(
            "Legacy sign-in did not return tokens.",
            code="COGNITO_AUTH_FAILED",
            status_code=401,
        )
    id_token = str(auth_result.get("IdToken") or "").strip()
    access_token = str(auth_result.get("AccessToken") or "").strip()
    if id_token:
        return verify_cognito_token(id_token)
    if access_token:
        return verify_cognito_token(access_token)
    raise CognitoLegacyAuthError(
        "Legacy sign-in did not return usable tokens.",
        code="COGNITO_AUTH_FAILED",
        status_code=401,
    )


def _call_cognito(method_name: str, **kwargs: Any) -> Any:
    if not is_enabled():
        raise CognitoLegacyAuthError(
            "Legacy Cognito auth is not configured.",
            code="COGNITO_NOT_CONFIGURED",
            status_code=503,
        )
    method = getattr(_cognito, method_name)
    try:
        return method(**kwargs)
    except ClientError as exc:
        raise _map_client_error(exc) from exc


def _list_users(*, filter_expression: str) -> list[Dict[str, Any]]:
    try:
        response = _cognito.list_users(
            UserPoolId=config.COGNITO_USER_POOL_ID,
            Filter=filter_expression,
            Limit=1,
        )
    except ClientError as exc:
        raise _map_client_error(exc) from exc
    users = response.get("Users") or []
    return [user for user in users if isinstance(user, dict)]


def _user_to_claims(user: Dict[str, Any]) -> Dict[str, Any]:
    attributes = user.get("Attributes") or []
    claim_map: Dict[str, Any] = {
        "cognito:username": str(user.get("Username") or "").strip(),
        "cognito_user_status": str(user.get("UserStatus") or "").strip(),
        "enabled": bool(user.get("Enabled", True)),
    }
    if isinstance(attributes, list):
        for item in attributes:
            if not isinstance(item, dict):
                continue
            name = str(item.get("Name") or "").strip()
            if not name:
                continue
            claim_map[name] = item.get("Value")
    return claim_map


def _map_client_error(exc: ClientError) -> CognitoLegacyAuthError:
    error = exc.response.get("Error", {}) if isinstance(exc.response, dict) else {}
    code = str(error.get("Code") or "").strip() or exc.__class__.__name__
    message = str(error.get("Message") or "").strip() or "Legacy Cognito auth failed."

    if code in ("NotAuthorizedException", "UserNotFoundException"):
        return CognitoLegacyAuthError(
            "Incorrect email, username, or password.",
            code=code,
            status_code=401,
        )
    if code == "UserNotConfirmedException":
        return CognitoLegacyAuthError(
            "Email not verified yet. Verify your email to finish signing in.",
            code=code,
            status_code=403,
        )
    if code in ("CodeMismatchException", "ExpiredCodeException"):
        return CognitoLegacyAuthError(
            "Invalid or expired verification code.",
            code=code,
            status_code=400,
        )
    if code == "UsernameExistsException":
        return CognitoLegacyAuthError(
            "An account with this email already exists.",
            code=code,
            status_code=409,
        )
    if code in ("TooManyRequestsException", "LimitExceededException"):
        return CognitoLegacyAuthError(
            "Too many attempts. Please try again later.",
            code=code,
            status_code=429,
        )
    return CognitoLegacyAuthError(
        message,
        code=code,
        status_code=400,
    )


def _fetch_cognito_jwks(user_pool_id: str) -> Dict[str, Any]:
    cache_key = f"{config.COGNITO_REGION}:{user_pool_id}"
    cached = _jwks_cache.get(cache_key)
    now = time.time()
    if cached and now - cached[0] < 300:
        return cached[1]

    issuer = (
        f"https://cognito-idp.{config.COGNITO_REGION}.amazonaws.com/"
        f"{user_pool_id}"
    )
    with urllib.request.urlopen(f"{issuer}/.well-known/jwks.json", timeout=10) as response:
        payload = json.loads(response.read().decode("utf-8"))
    _jwks_cache[cache_key] = (now, payload if isinstance(payload, dict) else {})
    return _jwks_cache[cache_key][1]


def _extract_token_audiences(payload: Dict[str, Any]) -> list[str]:
    audiences: list[str] = []

    aud = payload.get("aud")
    if isinstance(aud, str) and aud.strip():
        audiences.append(aud.strip())
    elif isinstance(aud, list):
        for value in aud:
            text = str(value or "").strip()
            if text:
                audiences.append(text)

    client_id = payload.get("client_id")
    if isinstance(client_id, str) and client_id.strip():
        audiences.append(client_id.strip())

    seen: set[str] = set()
    unique: list[str] = []
    for value in audiences:
        if value in seen:
            continue
        seen.add(value)
        unique.append(value)
    return unique


def _escape_filter_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')
