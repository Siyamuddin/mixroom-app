from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone
from typing import Any, Dict, Optional

from . import config

_USERNAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9_-]{0,28}[a-z0-9])?$")
_RESERVED_USERNAMES = {
    "about",
    "account",
    "admin",
    "administrator",
    "ads",
    "api",
    "app",
    "auth",
    "billing",
    "comment",
    "comments",
    "contact",
    "create",
    "discover",
    "download",
    "edit",
    "email",
    "explore",
    "feed",
    "help",
    "home",
    "legal",
    "login",
    "logout",
    "me",
    "messages",
    "mixroom",
    "mixroomapp",
    "mixroomofficial",
    "new",
    "notifications",
    "official",
    "payments",
    "privacy",
    "root",
    "search",
    "security",
    "settings",
    "signup",
    "staff",
    "studio",
    "subscribe",
    "subscription",
    "subscriptions",
    "support",
    "system",
    "team",
    "terms",
    "trending",
    "upload",
    "uploads",
    "user",
    "users",
    "verify",
    "www",
}
_ALLOWED_MUSIC_PROFILES = {
    "producer",
    "artist",
    "songwriter",
    "audio_engineer",
    "student",
    "music_enthusiast",
    "beginner",
    "music_for_work",
}
_WELCOME_SEEN_ONBOARDING_STATE = "signup_complete_welcome_seen"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize_optional_string(value: Any) -> Optional[str]:
    raw = str(value or "").strip()
    return raw or None


def _normalize_optional_name(value: Any, field_name: str) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    if len(raw) > 60:
        raise ValueError(f"{field_name} must be 60 characters or fewer.")
    return raw


def _normalize_iso_datetime(value: Any, field_name: str) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} must be a valid ISO 8601 datetime.") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    else:
        parsed = parsed.astimezone(timezone.utc)
    return parsed.isoformat()


def _claim_str(claims: Dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = str(claims.get(key) or "").strip()
        if value:
            return value
    return ""


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


def _display_name_from_email(email: str) -> str:
    local = (email or "").split("@")[0].strip()
    if not local:
        return "Mixroom User"
    spaced = " ".join(part for part in local.replace(".", " ").replace("_", " ").replace("-", " ").split() if part)
    if not spaced:
        return "Mixroom User"
    return " ".join(part[:1].upper() + part[1:] for part in spaced.split())


def _display_name_from_parts(
    given_name: Optional[str],
    family_name: Optional[str],
) -> Optional[str]:
    parts = [
        str(given_name or "").strip(),
        str(family_name or "").strip(),
    ]
    safe = " ".join(part for part in parts if part)
    return safe or None


def _provider_from_claims(claims: Dict[str, Any]) -> str:
    direct_provider = _claim_str(claims, "provider", "auth_provider").lower()
    if direct_provider in ("email", "google", "apple", "kakao"):
        return direct_provider
    raw_identities = _claim_str(claims, "identities")
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


def normalize_username(value: Any) -> Optional[str]:
    raw = str(value or "").strip().lower()
    return raw or None


def validate_username(username: Optional[str]) -> Optional[str]:
    if username is None:
        return None
    if len(username) < 1:
        return "Username must be at least 1 character."
    if len(username) > 30:
        return "Username must be 30 characters or fewer."
    if username in _RESERVED_USERNAMES:
        return "That username is reserved."
    if "--" in username or "__" in username or "-_" in username or "_-" in username:
        return "Username cannot contain repeated separators."
    if not _USERNAME_RE.fullmatch(username):
        return "Username must use only lowercase letters, numbers, underscores, or hyphens, and cannot start or end with a separator."
    return None


def normalize_bio(value: Any) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    if len(raw) > 160:
        raise ValueError("Bio must be 160 characters or fewer.")
    return raw


def normalize_avatar_url(value: Any) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    lowered = raw.lower()
    if not (lowered.startswith("https://") or lowered.startswith("http://")):
        raise ValueError("Avatar URL must start with http:// or https://.")
    if len(raw) > 500:
        raise ValueError("Avatar URL must be 500 characters or fewer.")
    return raw


def _normalize_birthdate(value: Any) -> Optional[str]:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = date.fromisoformat(raw)
    except ValueError as exc:
        raise ValueError("Birthdate must be in YYYY-MM-DD format.") from exc
    today = datetime.now(timezone.utc).date()
    if parsed > today:
        raise ValueError("Birthdate cannot be in the future.")
    age = today.year - parsed.year - (
        (today.month, today.day) < (parsed.month, parsed.day)
    )
    if age < config.MINIMUM_SIGNUP_AGE_YEARS:
        raise ValueError(
            f"You must be at least {config.MINIMUM_SIGNUP_AGE_YEARS} years old to use Mixroom."
        )
    return parsed.isoformat()


def normalize_music_profile(value: Any) -> Optional[str]:
    raw = str(value or "").strip().lower()
    if not raw:
        return None
    if raw not in _ALLOWED_MUSIC_PROFILES:
        raise ValueError("Music profile must be one of the supported options.")
    return raw


def _default_onboarding_state(record: Dict[str, Any]) -> str:
    existing = str(record.get("onboarding_state") or "").strip()
    if existing and existing not in ("bootstrap_only", "profile_ready"):
        return existing
    has_required_signup_profile = bool(
        record.get("username")
        and record.get("accepted_terms_version")
        and record.get("accepted_privacy_version")
    )
    if has_required_signup_profile:
        return "signup_complete"
    if (
        record.get("username")
        or record.get("bio")
        or record.get("avatar_url")
        or record.get("given_name")
        or record.get("family_name")
        or record.get("birthdate")
    ):
        return "profile_ready"
    if existing:
        return existing
    return "bootstrap_only"


def default_onboarding_state(record: Dict[str, Any]) -> str:
    return _default_onboarding_state(record)


def build_user_profile_from_claims(
    claims: Dict[str, Any],
    *,
    existing: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    now = _utc_now_iso()
    current = existing or {}

    user_id = _claim_str(claims, "sub")
    if not user_id:
        raise ValueError("Missing authenticated user ID claim.")

    email = _claim_str(claims, "email").lower()
    given_name = _normalize_optional_name(
        current.get("given_name") or _claim_str(claims, "given_name"),
        "Given name",
    )
    family_name = _normalize_optional_name(
        current.get("family_name") or _claim_str(claims, "family_name"),
        "Family name",
    )
    claim_display_name = _claim_str(claims, "name")
    inferred_display_name = _display_name_from_parts(given_name, family_name)
    display_name = str(current.get("display_name") or "").strip()
    if not display_name:
        display_name = claim_display_name
    if not display_name:
        display_name = inferred_display_name or ""
    if not display_name:
        display_name = _display_name_from_email(email)

    username = normalize_username(current.get("username"))

    record = {
        "user_id": user_id,
        "email": email or str(current.get("email") or "").strip().lower(),
        "email_lc": (email or str(current.get("email_lc") or "").strip().lower()) or None,
        "display_name": display_name,
        "email_verified": _claim_bool(claims, "email_verified")
        if "email_verified" in claims
        else bool(current.get("email_verified")),
        "cognito_username": _claim_str(claims, "cognito:username") or str(current.get("cognito_username") or "").strip(),
        "auth_provider": str(current.get("auth_provider") or "").strip() or _provider_from_claims(claims),
        "username": username or None,
        "username_lc": username.lower() if username else None,
        "given_name": given_name,
        "family_name": family_name,
        "birthdate": _normalize_birthdate(current.get("birthdate")),
        "music_profile": normalize_music_profile(current.get("music_profile")),
        "avatar_url": current.get("avatar_url"),
        "bio": current.get("bio"),
        "profile_status": str(current.get("profile_status") or "active").strip() or "active",
        "onboarding_state": str(current.get("onboarding_state") or "").strip(),
        "accepted_terms_version": _normalize_optional_string(
            current.get("accepted_terms_version")
        ),
        "accepted_privacy_version": _normalize_optional_string(
            current.get("accepted_privacy_version")
        ),
        "accepted_at": _normalize_optional_string(current.get("accepted_at")),
        "newsletter_opt_in": _claim_bool(current, "newsletter_opt_in"),
        "newsletter_opt_in_at": _normalize_optional_string(
            current.get("newsletter_opt_in_at")
        ),
        "created_at": current.get("created_at") or now,
        "updated_at": now,
        "last_seen_at": now,
        "bootstrap_source": "native_auth_token"
        if _claim_str(claims, "iss") == config.APP_AUTH_ISSUER
        else "cognito_claims",
        "schema_version": 4,
    }
    record["onboarding_state"] = _default_onboarding_state(record)
    return record


def user_profile_needs_claim_sync(
    claims: Dict[str, Any],
    existing: Optional[Dict[str, Any]] = None,
) -> bool:
    current = existing or {}
    if not current:
        return True

    claim_user_id = _claim_str(claims, "sub")
    if not claim_user_id or str(current.get("user_id") or "").strip() != claim_user_id:
        return True

    claim_email = _claim_str(claims, "email").lower()
    current_email = str(current.get("email") or "").strip().lower()
    if claim_email and claim_email != current_email:
        return True

    current_email_lc = str(current.get("email_lc") or "").strip().lower()
    if current_email and current_email_lc != current_email:
        return True

    claim_email_verified_present = "email_verified" in claims
    claim_email_verified = _claim_bool(claims, "email_verified")
    current_email_verified = bool(current.get("email_verified"))
    if claim_email_verified_present and current_email_verified != claim_email_verified:
        return True

    claim_cognito_username = _claim_str(claims, "cognito:username")
    current_cognito_username = str(current.get("cognito_username") or "").strip()
    if claim_cognito_username and claim_cognito_username != current_cognito_username:
        return True

    claim_provider = _provider_from_claims(claims)
    current_provider = str(current.get("auth_provider") or "").strip().lower()
    if claim_provider and not current_provider:
        return True
    if claim_provider and current_provider and claim_provider != current_provider:
        return True

    claim_given_name = _claim_str(claims, "given_name")
    current_given_name = str(current.get("given_name") or "").strip()
    if claim_given_name and not current_given_name:
        return True

    claim_family_name = _claim_str(claims, "family_name")
    current_family_name = str(current.get("family_name") or "").strip()
    if claim_family_name and not current_family_name:
        return True

    claim_name = _claim_str(claims, "name")
    current_display_name = str(current.get("display_name") or "").strip()
    if claim_name and not current_display_name:
        return True

    if "profile_status" not in current or not str(current.get("profile_status") or "").strip():
        return True
    if "schema_version" not in current:
        return True

    username = normalize_username(current.get("username"))
    username_lc = str(current.get("username_lc") or "").strip().lower() or None
    if username != username_lc:
        return True

    return False


def apply_user_profile_patch(
    current: Dict[str, Any],
    patch: Dict[str, Any],
) -> Dict[str, Any]:
    record = dict(current)
    now = _utc_now_iso()

    if "display_name" in patch:
        display_name = str(patch.get("display_name") or "").strip()
        if not display_name:
            raise ValueError("Display name cannot be empty.")
        if len(display_name) > 80:
            raise ValueError("Display name must be 80 characters or fewer.")
        record["display_name"] = display_name

    if "username" in patch:
        username = normalize_username(patch.get("username"))
        username_error = validate_username(username)
        if username_error:
            raise ValueError(username_error)
        record["username"] = username
        record["username_lc"] = username
        if username and "display_name" not in patch:
            current_display_name = str(record.get("display_name") or "").strip()
            email_fallback_display_name = _display_name_from_email(
                str(record.get("email") or "")
            )
            if (
                not current_display_name
                or current_display_name.lower().startswith("mixroom-user")
                or current_display_name.lower()
                == email_fallback_display_name.lower()
            ):
                record["display_name"] = username

    if "given_name" in patch:
        record["given_name"] = _normalize_optional_name(
            patch.get("given_name"),
            "First name",
        )

    if "family_name" in patch:
        record["family_name"] = _normalize_optional_name(
            patch.get("family_name"),
            "Last name",
        )

    if "birthdate" in patch:
        record["birthdate"] = _normalize_birthdate(patch.get("birthdate"))

    if "music_profile" in patch:
        record["music_profile"] = normalize_music_profile(
            patch.get("music_profile")
        )

    if "bio" in patch:
        record["bio"] = normalize_bio(patch.get("bio"))

    if "avatar_url" in patch:
        record["avatar_url"] = normalize_avatar_url(patch.get("avatar_url"))

    if "accepted_terms_version" in patch:
        accepted_terms_version = _normalize_optional_string(
            patch.get("accepted_terms_version")
        )
        if accepted_terms_version is None:
            raise ValueError("Accepted terms version cannot be empty.")
        record["accepted_terms_version"] = accepted_terms_version

    if "accepted_privacy_version" in patch:
        accepted_privacy_version = _normalize_optional_string(
            patch.get("accepted_privacy_version")
        )
        if accepted_privacy_version is None:
            raise ValueError("Accepted privacy version cannot be empty.")
        record["accepted_privacy_version"] = accepted_privacy_version

    if "accepted_at" in patch:
        record["accepted_at"] = _normalize_iso_datetime(
            patch.get("accepted_at"),
            "Accepted at",
        )

    if "newsletter_opt_in" in patch:
        newsletter_opt_in = patch.get("newsletter_opt_in")
        if not isinstance(newsletter_opt_in, bool):
            raise ValueError("Newsletter opt-in must be a boolean.")
        record["newsletter_opt_in"] = newsletter_opt_in
        if not newsletter_opt_in:
            record["newsletter_opt_in_at"] = None

    if "newsletter_opt_in_at" in patch:
        record["newsletter_opt_in_at"] = _normalize_iso_datetime(
            patch.get("newsletter_opt_in_at"),
            "Newsletter opt-in at",
        )

    if record.get("accepted_terms_version") and record.get("accepted_privacy_version"):
        record["accepted_at"] = record.get("accepted_at") or now

    if record.get("newsletter_opt_in"):
        record["newsletter_opt_in_at"] = record.get("newsletter_opt_in_at") or now
    else:
        record["newsletter_opt_in_at"] = None

    requested_onboarding_state = str(patch.get("onboarding_state") or "").strip()

    record["updated_at"] = now
    record["last_seen_at"] = now
    record["onboarding_state"] = _default_onboarding_state(record)
    if (
        requested_onboarding_state == _WELCOME_SEEN_ONBOARDING_STATE
        and record["onboarding_state"] == "signup_complete"
    ):
        # Preserve the legacy welcome-complete marker so older clients stop
        # resending the same PATCH on every refresh. Newer clients should keep
        # welcome completion local-only.
        record["onboarding_state"] = _WELCOME_SEEN_ONBOARDING_STATE
    record["schema_version"] = max(4, int(record.get("schema_version") or 1))
    return record
