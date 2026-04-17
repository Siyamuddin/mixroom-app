from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from . import config
from .secrets import load_stibee_access_token

_logger = logging.getLogger(__name__)


class StibeeError(RuntimeError):
    pass


class StibeeConfigError(StibeeError):
    pass


class StibeeSyncError(StibeeError):
    pass


def normalize_locale_code(value: Any) -> str:
    safe = str(value or "").strip().lower()
    if safe.startswith("ko"):
        return "ko"
    return "en"


def sync_user_profile(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
    locale_code: Any = None,
) -> None:
    if not _integration_requested():
        return

    email = str(next_profile.get("email") or "").strip().lower()
    if not email:
        raise StibeeSyncError("Missing user email for Stibee sync.")

    locale = _resolved_locale_code(
        explicit_locale_code=locale_code,
        previous_profile=previous_profile,
        next_profile=next_profile,
    )
    client = _StibeeClient()

    if _should_sync_signup_list(
        previous_profile=previous_profile,
        next_profile=next_profile,
        locale_code=locale,
    ):
        try:
            client.upsert_subscriber(
                list_id=_app_signups_list_id(),
                email=email,
                status="subscribed",
                marketing_allowed=bool(next_profile.get("newsletter_opt_in")),
                fields=_build_signup_fields(next_profile=next_profile, locale_code=locale),
            )
        except StibeeError:
            _logger.exception(
                "Stibee signup-list sync failed.",
                extra={
                    "user_id": str(next_profile.get("user_id") or "").strip(),
                    "locale_code": locale,
                    "list_id": str(config.STIBEE_APP_SIGNUPS_LIST_ID or "").strip(),
                },
            )

    if _should_sync_newsletter(
        previous_profile=previous_profile,
        next_profile=next_profile,
        locale_code=locale,
    ):
        newsletter_opt_in = bool(next_profile.get("newsletter_opt_in"))
        client.upsert_subscriber(
            list_id=_newsletter_list_id(),
            email=email,
            status="subscribed" if newsletter_opt_in else "unsubscribed",
            marketing_allowed=newsletter_opt_in,
            fields=_build_newsletter_fields(
                next_profile=next_profile,
                locale_code=locale,
                newsletter_opt_in=newsletter_opt_in,
            ),
        )


class _StibeeClient:
    def __init__(self) -> None:
        try:
            self._access_token = load_stibee_access_token()
        except Exception as exc:
            raise StibeeConfigError("Stibee is not configured.") from exc
        self._base_url = _stibee_base_url()

    def upsert_subscriber(
        self,
        *,
        list_id: str,
        email: str,
        status: str,
        marketing_allowed: bool,
        fields: Optional[Dict[str, Any]] = None,
    ) -> None:
        safe_list_id = str(list_id or "").strip()
        if not safe_list_id:
            raise StibeeConfigError("Missing Stibee list ID.")

        payload = {
            "subscriber": {
                "email": str(email or "").strip().lower(),
                "status": status,
                "marketingAllowed": bool(marketing_allowed),
                "fields": fields or {},
            },
            "updateEnabled": True,
        }
        self._request(
            method="POST",
            path=f"/lists/{safe_list_id}/subscribers",
            payload=payload,
        )

    def _request(
        self,
        *,
        method: str,
        path: str,
        payload: Optional[Dict[str, Any]] = None,
    ) -> bytes:
        request = urllib.request.Request(
            f"{self._base_url}{path}",
            data=(
                json.dumps(payload, ensure_ascii=True).encode("utf-8")
                if payload is not None
                else None
            ),
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "AccessToken": self._access_token,
            },
            method=method,
        )
        try:
            with urllib.request.urlopen(
                request,
                timeout=config.HTTP_TIMEOUT_SECONDS,
            ) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            payload = _parse_json_payload(exc.read())
            code = str(payload.get("code") or "").strip()
            message = str(payload.get("message") or "").strip()
            raise StibeeSyncError(
                f"Stibee request failed ({exc.code}{f', {code}' if code else ''}{f', {message}' if message else ''})."
            ) from exc
        except urllib.error.URLError as exc:
            raise StibeeSyncError("Stibee request failed.") from exc
        except Exception as exc:
            raise StibeeSyncError("Stibee request failed.") from exc


def _integration_requested() -> bool:
    return any(
        (
            config.STIBEE_ACCESS_TOKEN,
            config.STIBEE_ACCESS_TOKEN_SECRET_ARN,
            config.STIBEE_APP_SIGNUPS_LIST_ID,
            config.STIBEE_NEWSLETTER_LIST_ID,
        )
    )


def _stibee_base_url() -> str:
    return str(config.STIBEE_API_BASE_URL or "https://api.stibee.com/v2").strip().rstrip("/")


def _app_signups_list_id() -> str:
    safe = str(config.STIBEE_APP_SIGNUPS_LIST_ID or "").strip()
    if not safe:
        raise StibeeConfigError("Stibee app signups list is not configured.")
    return safe


def _newsletter_list_id() -> str:
    safe = str(config.STIBEE_NEWSLETTER_LIST_ID or "").strip()
    if not safe:
        raise StibeeConfigError("Stibee newsletter list is not configured.")
    return safe


def _should_sync_signup_list(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
    locale_code: str,
) -> bool:
    if not _is_signup_complete(next_profile):
        return False
    if not _is_signup_complete(previous_profile):
        return True
    return _signup_fields_changed(
        previous_profile=previous_profile,
        next_profile=next_profile,
        locale_code=locale_code,
    )


def _should_sync_newsletter(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
    locale_code: Any,
) -> bool:
    previous_opt_in = bool((previous_profile or {}).get("newsletter_opt_in"))
    next_opt_in = bool(next_profile.get("newsletter_opt_in"))
    if previous_opt_in != next_opt_in:
        return True
    if not (previous_opt_in or next_opt_in):
        return False
    return _newsletter_fields_changed(
        previous_profile=previous_profile,
        next_profile=next_profile,
        locale_code=locale_code,
    )


def _build_signup_fields(
    *,
    next_profile: Dict[str, Any],
    locale_code: str,
) -> Dict[str, Any]:
    return _build_base_fields(
        next_profile=next_profile,
        locale_code=locale_code,
        event_date=_profile_datetime_str(next_profile.get("accepted_at"))
        or _profile_datetime_str(next_profile.get("created_at")),
    )


def _build_newsletter_fields(
    *,
    next_profile: Dict[str, Any],
    locale_code: str,
    newsletter_opt_in: bool,
) -> Dict[str, Any]:
    fields = _build_base_fields(
        next_profile=next_profile,
        locale_code=locale_code,
        event_date=_profile_datetime_str(next_profile.get("newsletter_opt_in_at"))
        or _profile_datetime_str(next_profile.get("updated_at")),
    )
    _maybe_set_field(
        fields,
        config.STIBEE_SUBSCRIPTION_STATUS_FIELD_KEY,
        "subscribed" if newsletter_opt_in else "unsubscribed",
    )
    return fields


def _build_base_fields(
    *,
    next_profile: Dict[str, Any],
    locale_code: str,
    event_date: Optional[str],
) -> Dict[str, Any]:
    fields: Dict[str, Any] = {}
    _maybe_set_field(fields, config.STIBEE_LANGUAGE_FIELD_KEY, locale_code)
    _maybe_set_field(fields, config.STIBEE_NAME_FIELD_KEY, _display_name(next_profile))
    _maybe_set_field(fields, config.STIBEE_SOURCE_FIELD_KEY, "app")
    _maybe_set_field(fields, config.STIBEE_DATE_FIELD_KEY, event_date)
    _maybe_set_field(
        fields,
        config.STIBEE_USER_ID_FIELD_KEY,
        str(next_profile.get("user_id") or "").strip(),
    )
    return fields


def _resolved_locale_code(
    *,
    explicit_locale_code: Any,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
) -> str:
    explicit = str(explicit_locale_code or "").strip()
    if explicit:
        return normalize_locale_code(explicit)

    for profile in (next_profile, previous_profile or {}):
        candidate = str((profile or {}).get("locale_code") or "").strip()
        if candidate:
            return normalize_locale_code(candidate)
    return "en"


def _signup_fields_changed(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
    locale_code: str,
) -> bool:
    previous_locale = _resolved_locale_code(
        explicit_locale_code=None,
        previous_profile=None,
        next_profile=previous_profile or {},
    )
    if previous_locale != locale_code:
        return True
    return _name_field_changed(previous_profile=previous_profile, next_profile=next_profile)


def _newsletter_fields_changed(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
    locale_code: str,
) -> bool:
    previous_locale = _resolved_locale_code(
        explicit_locale_code=None,
        previous_profile=None,
        next_profile=previous_profile or {},
    )
    if previous_locale != locale_code:
        return True
    return _name_field_changed(previous_profile=previous_profile, next_profile=next_profile)


def _name_field_changed(
    *,
    previous_profile: Optional[Dict[str, Any]],
    next_profile: Dict[str, Any],
) -> bool:
    if not str(config.STIBEE_NAME_FIELD_KEY or "").strip():
        return False
    return _display_name(previous_profile or {}) != _display_name(next_profile)


def _display_name(profile: Dict[str, Any]) -> str:
    display_name = str(profile.get("display_name") or "").strip()
    if display_name:
        return display_name
    parts = [
        str(profile.get("given_name") or "").strip(),
        str(profile.get("family_name") or "").strip(),
    ]
    return " ".join(part for part in parts if part).strip()


def _maybe_set_field(fields: Dict[str, Any], key: str, value: Any) -> None:
    safe_key = str(key or "").strip()
    if not safe_key:
        return
    safe_value = str(value or "").strip()
    if not safe_value:
        return
    fields[safe_key] = safe_value


def _profile_datetime_str(value: Any) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return raw
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    else:
        parsed = parsed.astimezone(timezone.utc)
    return parsed.isoformat()


def _is_signup_complete(profile: Optional[Dict[str, Any]]) -> bool:
    state = str((profile or {}).get("onboarding_state") or "").strip().lower()
    return state == "signup_complete" or state.startswith("signup_complete_")


def _parse_json_payload(payload: bytes) -> Dict[str, Any]:
    if not payload:
        return {}
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except Exception:
        return {}
    return decoded if isinstance(decoded, dict) else {}
