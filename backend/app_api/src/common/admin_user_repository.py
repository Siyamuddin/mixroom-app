from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from typing import Any, Dict
from uuid import uuid4

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from boto3.dynamodb.conditions import Attr
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    Attr = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import config
from .billing_catalog import catalog_plan_by_code, infer_plan_code
from .billing_catalog_repository import BillingCatalogRepository
from .collaboration_repository import CollaborationRepository, education_seat_limit
from .models import (
    choose_primary_subscription,
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    legacy_tier_for_plan_code,
    normalize_plan_code,
    normalize_provider,
    normalize_status,
    status_has_active_access,
    subscription_effective_status,
    free_entitlement,
)
from .native_auth import (
    _hash_password,
    _looks_like_email,
    _new_user_id,
    _normalize_email,
    _validate_password_policy,
)
from .repository import UsernameClaimConflictError
from .users import normalize_username, validate_username
try:
    from .repository import BillingRepository
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    BillingRepository = None


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _safe_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    text = _safe_str(value).lower()
    if text == "true":
        return True
    if text == "false":
        return False
    return False


def _safe_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _parse_iso(value: Any) -> datetime | None:
    raw = _safe_str(value)
    if not raw:
        return None
    try:
        normalized = raw.replace("Z", "+00:00") if raw.endswith("Z") else raw
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _datetime_to_iso(value: Any) -> str:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    return _safe_str(value)


def _expected_admin_first_name(email: str) -> str:
    local = _safe_str(email).lower().split("@", 1)[0]
    return local.replace("-", ".").replace("_", ".").split(".", 1)[0]


def _stable_admin_org_id(plan_code: str, user_id: str) -> str:
    digest = hashlib.sha256(_safe_str(user_id).encode("utf-8")).hexdigest()[:16]
    return f"admin-override-{normalize_plan_code(plan_code)}-{digest}"


def _later_iso(current: str, candidate: str) -> str:
    current_dt = _parse_iso(current)
    candidate_dt = _parse_iso(candidate)
    if candidate_dt is None:
        return current
    if current_dt is None or candidate_dt > current_dt:
        return candidate
    return current


def _normalize_query(value: Any) -> str:
    return _safe_str(value).lower()


def _normalize_subscription_filter(value: Any) -> str:
    normalized = _safe_str(value).lower()
    return normalized if normalized in {"paying", "granted"} else "all"


def _limit_value(value: Any, default: int = 24, maximum: int = 100) -> int:
    try:
        numeric = int(value or default)
    except (TypeError, ValueError):
        numeric = default
    return max(1, min(numeric, maximum))


class AdminUserNotFoundError(Exception):
    pass


class AdminDeleteRequiresForceError(Exception):
    def __init__(self, message: str, *, snapshot: Dict[str, Any]) -> None:
        super().__init__(message)
        self.snapshot = snapshot


class AdminUserRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._cognito = None
        self._users = None
        self._ai_usage_state = None
        self._entitlements = None
        self._subscriptions = None
        self._customer_links = None
        self._purchase_tokens = None
        self._tombstones = None
        self._entitlement_overrides = None
        self._catalog_repo = BillingCatalogRepository()
        self._collaboration_repo = CollaborationRepository()
        self._billing_repo = (
            BillingRepository()
            if boto3 is not None and BillingRepository is not None
            else None
        )

        if self._ddb is not None and config.USERS_TABLE:
            self._users = self._ddb.Table(config.USERS_TABLE)
        if self._ddb is not None and config.AI_USAGE_STATE_TABLE:
            self._ai_usage_state = self._ddb.Table(config.AI_USAGE_STATE_TABLE)
        if self._ddb is not None and config.ENTITLEMENTS_TABLE:
            self._entitlements = self._ddb.Table(config.ENTITLEMENTS_TABLE)
        if self._ddb is not None and config.SUBSCRIPTIONS_TABLE:
            self._subscriptions = self._ddb.Table(config.SUBSCRIPTIONS_TABLE)
        if self._ddb is not None and config.CUSTOMER_LINKS_TABLE:
            self._customer_links = self._ddb.Table(config.CUSTOMER_LINKS_TABLE)
        if self._ddb is not None and config.PURCHASE_TOKENS_TABLE:
            self._purchase_tokens = self._ddb.Table(config.PURCHASE_TOKENS_TABLE)
        if self._ddb is not None and config.USER_TOMBSTONES_TABLE:
            self._tombstones = self._ddb.Table(config.USER_TOMBSTONES_TABLE)
        if self._ddb is not None and config.ADMIN_ENTITLEMENT_OVERRIDES_TABLE:
            self._entitlement_overrides = self._ddb.Table(
                config.ADMIN_ENTITLEMENT_OVERRIDES_TABLE
            )
        if boto3 is not None and config.COGNITO_USER_POOL_ID:
            self._cognito = boto3.client("cognito-idp")

    def search_users(
        self,
        *,
        query: str = "",
        limit: int = 24,
        subscription_filter: str = "all",
    ) -> Dict[str, Any]:
        normalized_query = _normalize_query(query)
        normalized_subscription_filter = _normalize_subscription_filter(
            subscription_filter
        )
        result_limit = _limit_value(limit)
        warnings: list[str] = []

        if normalized_subscription_filter != "all":
            candidate_user_ids = self._list_subscription_candidate_user_ids(
                normalized_subscription_filter,
                warnings=warnings,
            )
        elif normalized_query:
            candidate_user_ids = self._search_candidate_user_ids(
                normalized_query,
                limit=result_limit,
                warnings=warnings,
            )
        else:
            candidate_user_ids = self._list_recent_candidate_user_ids(
                limit=result_limit,
                warnings=warnings,
            )

        records: list[Dict[str, Any]] = []
        for user_id in candidate_user_ids:
            record = self._load_user_record(user_id, warnings)
            if not record:
                continue
            if normalized_query and not self._matches_query(record, normalized_query):
                continue
            records.append(record)

        records.sort(
            key=lambda item: (
                _parse_iso(item.get("last_seen_at")).timestamp()
                if _parse_iso(item.get("last_seen_at")) is not None
                else 0.0,
                _parse_iso(item.get("updated_at")).timestamp()
                if _parse_iso(item.get("updated_at")) is not None
                else 0.0,
                _parse_iso(item.get("created_at")).timestamp()
                if _parse_iso(item.get("created_at")) is not None
                else 0.0,
                item.get("email") or item.get("username") or item.get("user_id") or "",
            ),
            reverse=True,
        )
        visible_records = records[:result_limit]

        return {
            "generated_at": _utc_now_iso(),
            "query": _safe_str(query),
            "subscription_filter": normalized_subscription_filter,
            "limit": result_limit,
            "total_matches": len(records),
            "has_more": len(records) > result_limit,
            "warnings": warnings,
            "users": visible_records,
            "sources": {
                "users_table": self._users is not None,
                "ai_usage_state": self._ai_usage_state is not None,
                "entitlements": self._entitlements is not None,
                "subscriptions": self._subscriptions is not None,
                "customer_links": self._customer_links is not None,
                "auth_accounts": bool(config.AUTH_ACCOUNTS_TABLE),
                "auth_sessions": bool(config.AUTH_SESSIONS_TABLE),
                "cognito_users": self._cognito is not None,
            },
        }

    def create_username_account(
        self,
        *,
        username: str,
        display_name: str,
        password: str,
        email: str = "",
        created_by_user_id: str,
        created_by_email: str,
    ) -> Dict[str, Any]:
        if self._billing_repo is None:
            raise RuntimeError("Billing repository is not available.")

        safe_username = normalize_username(username)
        username_error = validate_username(safe_username)
        if username_error:
            raise ValueError(username_error)
        safe_display_name = _safe_str(display_name)
        if not safe_display_name:
            raise ValueError("Name is required.")
        if len(safe_display_name) > 80:
            raise ValueError("Name must be 80 characters or fewer.")
        safe_password = str(password or "")
        if not safe_password:
            raise ValueError("Password is required.")
        _validate_password_policy(safe_password)

        safe_email = _normalize_email(email)
        if safe_email and not _looks_like_email(safe_email):
            raise ValueError("Email must be valid when provided.")
        if safe_email and self._billing_repo.get_auth_account_by_email(safe_email):
            raise ValueError("An account with this email already exists.")
        if self._billing_repo.get_user_profile_by_username(safe_username or ""):
            raise ValueError("That username is already taken.")

        now = _utc_now_iso()
        user_id = _new_user_id()
        password_salt = secrets.token_hex(16)
        account = {
            "user_id": user_id,
            "email": safe_email,
            "email_lc": safe_email or None,
            "auth_provider": "email",
            "email_verified": True,
            "email_verification_source": "admin_provisioned"
            if safe_email
            else "admin_provisioned_no_email",
            "password_salt": password_salt,
            "password_hash": _hash_password(password=safe_password, salt=password_salt),
            "password_iterations": 210000,
            "verification_code_hash": "",
            "verification_expires_at": "",
            "verification_sent_at": "",
            "password_reset_code_hash": "",
            "password_reset_expires_at": "",
            "created_at": now,
            "updated_at": now,
            "admin_provisioned": True,
            "admin_provisioned_at": now,
            "admin_provisioned_by_user_id": _safe_str(created_by_user_id),
            "admin_provisioned_by_email": _safe_str(created_by_email).lower(),
        }
        profile = {
            "user_id": user_id,
            "email": safe_email,
            "email_lc": safe_email or None,
            "display_name": safe_display_name,
            "email_verified": True,
            "cognito_username": "",
            "auth_provider": "email",
            "username": safe_username,
            "username_lc": safe_username,
            "given_name": None,
            "family_name": None,
            "birthdate": None,
            "music_profile": None,
            "avatar_url": None,
            "bio": None,
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "admin_provisioned",
            "accepted_privacy_version": "admin_provisioned",
            "accepted_at": now,
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "telemetry_enabled": True,
            "telemetry_enabled_at": now,
            "locale_code": None,
            "created_at": now,
            "updated_at": now,
            "last_seen_at": now,
            "bootstrap_source": "admin_username_account",
            "schema_version": 5,
            "admin_provisioned": True,
            "admin_provisioned_at": now,
            "admin_provisioned_by_user_id": _safe_str(created_by_user_id),
            "admin_provisioned_by_email": _safe_str(created_by_email).lower(),
        }
        if not safe_email:
            account.pop("email_lc", None)
            profile.pop("email_lc", None)

        try:
            self._billing_repo.put_auth_account(account)
            self._billing_repo.upsert_user_profile(profile)
            if not self._billing_repo.get_entitlement(user_id):
                self._billing_repo.put_entitlement(
                    free_entitlement(user_id=user_id).to_dict()
                )
        except UsernameClaimConflictError as exc:
            self._billing_repo.delete_auth_account(user_id)
            self._billing_repo.delete_user_profile(user_id)
            raise ValueError("That username is already taken.") from exc
        except Exception:
            self._billing_repo.delete_auth_account(user_id)
            self._billing_repo.delete_user_profile(user_id)
            raise

        warnings: list[str] = []
        entitlement = self._get_entitlement(user_id, warnings)
        user_record = self._build_user_record(
            user_id,
            app_profile=profile,
            auth_account=account,
            cognito_profile={},
            warnings=warnings,
            entitlement=entitlement,
            subscriptions=[],
        )
        return {
            "created": True,
            "user_id": user_id,
            "username": safe_username,
            "email": safe_email,
            "user": user_record,
            "warnings": warnings,
        }

    def grant_prompt_allowance(
        self,
        *,
        user_id: str,
        prompt_count: int,
        granted_by_user_id: str,
        granted_by_email: str,
    ) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        if not safe_user_id:
            raise ValueError("User ID is required.")
        try:
            safe_prompt_count = int(prompt_count)
        except (TypeError, ValueError):
            raise ValueError("Prompt count must be a whole number.") from None
        if safe_prompt_count <= 0:
            raise ValueError("Prompt count must be greater than zero.")
        if safe_prompt_count > 500:
            raise ValueError("Prompt count must be 500 or less per grant.")
        if self._ai_usage_state is None:
            raise RuntimeError("AI usage state table is not configured.")

        warnings: list[str] = []
        app_profile = self._get_user_profile(safe_user_id, warnings)
        auth_account = self._get_auth_account(safe_user_id, warnings)
        cognito_profile = {}
        if not app_profile and not auth_account:
            raise AdminUserNotFoundError("User not found.")

        entitlement = self._get_entitlement(safe_user_id, warnings)
        subscriptions = self._list_subscriptions_for_user(safe_user_id, warnings)
        usage_state = self._get_ai_usage_state(safe_user_id, warnings)
        subscription_plan_code = normalize_plan_code(
            _safe_str(
                entitlement.get("plan_code")
                or usage_state.get("subscription_tier")
                or "free"
            )
        )
        current = _utc_now_iso()
        if not usage_state:
            self._ai_usage_state.put_item(
                Item={
                    "user_id": safe_user_id,
                    "ai_credits_used_today": 0,
                    "ai_tokens_used_month": 0,
                    "ai_prompts_used_today": 0,
                    "ai_prompts_used_week": 0,
                    "ai_last_reset": current[:10],
                    "ai_tokens_month_reset": current[:7],
                    "ai_prompts_day_reset": current[:10],
                    "ai_prompts_week_reset": current[:10],
                    "subscription_tier": subscription_plan_code,
                    "updated_at": current,
                    "admin_prompt_grants_total": 0,
                    "admin_prompt_grants_remaining": 0,
                },
            )

        response = self._ai_usage_state.update_item(
            Key={"user_id": safe_user_id},
            UpdateExpression=(
                "SET admin_prompt_grants_total = if_not_exists(admin_prompt_grants_total, :zero) + :prompt_count, "
                "admin_prompt_grants_remaining = if_not_exists(admin_prompt_grants_remaining, :zero) + :prompt_count, "
                "admin_prompt_grants_updated_at = :updated_at, "
                "admin_prompt_grants_updated_by = :updated_by, "
                "admin_prompt_grants_updated_email = :updated_email, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            ),
            ExpressionAttributeValues={
                ":zero": 0,
                ":prompt_count": safe_prompt_count,
                ":updated_at": current,
                ":updated_by": _safe_str(granted_by_user_id),
                ":updated_email": _safe_str(granted_by_email).lower(),
                ":subscription_tier": subscription_plan_code,
            },
            ReturnValues="ALL_NEW",
        )
        updated_state = response.get("Attributes") or {}
        user_record = self._build_user_record(
            safe_user_id,
            app_profile=app_profile,
            auth_account=auth_account,
            cognito_profile=cognito_profile,
            ai_usage_state=updated_state,
            warnings=warnings,
            entitlement=entitlement,
            subscriptions=subscriptions,
        )
        return {
            "granted": True,
            "user_id": safe_user_id,
            "granted_prompts": safe_prompt_count,
            "user": user_record,
            "warnings": warnings,
        }

    def apply_entitlement_override(
        self,
        *,
        user_id: str,
        plan_code: str,
        expires_at: str,
        reason: str,
        confirm_identifier: str,
        confirm_admin_first_name: str,
        granted_by_user_id: str,
        granted_by_email: str,
        seat_limit: int | None = None,
        organization_name: str = "",
    ) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        safe_plan_code = normalize_plan_code(plan_code)
        if not safe_user_id:
            raise ValueError("User ID is required.")
        if safe_plan_code not in {"starter", "producer", "studio", "enterprise", "education"}:
            raise ValueError("Admin overrides can only grant paid plans.")
        safe_reason = _safe_str(reason)
        if len(safe_reason) < 8:
            raise ValueError("Override reason must be at least 8 characters.")
        if self._entitlement_overrides is None:
            raise RuntimeError("Admin entitlement override audit table is not configured.")
        if self._billing_repo is None:
            raise RuntimeError("Billing repository is not available.")

        current = datetime.now(timezone.utc)
        expiry_dt = _parse_iso(expires_at)
        if expiry_dt is None:
            raise ValueError("Expiry date must be a valid ISO timestamp.")
        if expiry_dt <= current:
            raise ValueError("Expiry date must be in the future.")
        safe_expires_at = expiry_dt.isoformat()
        retention_expires_at = (expiry_dt + timedelta(days=90)).isoformat()

        expected_admin_name = _expected_admin_first_name(granted_by_email)
        if not expected_admin_name:
            raise ValueError("Admin email is required.")
        if _safe_str(confirm_admin_first_name).lower() != expected_admin_name:
            raise ValueError("Type your admin first name exactly to confirm.")

        warnings: list[str] = []
        app_profile = self._get_user_profile(safe_user_id, warnings)
        auth_account = self._get_auth_account(safe_user_id, warnings)
        if not app_profile and not auth_account:
            raise AdminUserNotFoundError("User not found.")
        cognito_profile = {}
        entitlement = self._get_entitlement(safe_user_id, warnings)
        subscriptions = self._list_subscriptions_for_user(safe_user_id, warnings)
        customer_links = self._list_customer_link_items(safe_user_id, warnings)
        snapshot = self._build_user_record(
            safe_user_id,
            app_profile=app_profile,
            auth_account=auth_account,
            cognito_profile=cognito_profile,
            warnings=warnings,
            customer_links=customer_links,
            entitlement=entitlement,
            subscriptions=subscriptions,
        )

        accepted_identifiers = {
            _safe_str(snapshot.get("email")).lower(),
            _safe_str(auth_account.get("email")).lower(),
            _safe_str(app_profile.get("email")).lower(),
            _safe_str(snapshot.get("username")).lower(),
            _safe_str(app_profile.get("username")).lower(),
            safe_user_id.lower(),
        }
        accepted_identifiers.discard("")
        if _safe_str(confirm_identifier).lower() not in accepted_identifiers:
            raise ValueError("Type the user's email, username, or user ID exactly to confirm.")

        plan = catalog_plan_by_code(safe_plan_code, catalog=self._catalog_repo.get_catalog())
        resolved_seat_limit = self._normalize_override_seat_limit(
            safe_plan_code,
            seat_limit,
            plan=plan,
        )

        created_at = current.isoformat()
        override_id = uuid4().hex
        subscription_id = f"admin_grant:{safe_plan_code}:{override_id}"
        product_code = f"{safe_plan_code}_admin_override"
        audit_record = {
            "override_id": override_id,
            "created_at": created_at,
            "updated_at": created_at,
            "status": "applying",
            "target_user_id": safe_user_id,
            "target_email": _safe_str(snapshot.get("email")).lower(),
            "target_username": _safe_str(snapshot.get("username")),
            "admin_user_id": _safe_str(granted_by_user_id),
            "admin_email": _safe_str(granted_by_email).lower(),
            "plan_code": safe_plan_code,
            "plan_label": _safe_str(plan.get("label")) or safe_plan_code.title(),
            "seat_limit": resolved_seat_limit,
            "effective_at": created_at,
            "expires_at": safe_expires_at,
            "retention_expires_at": retention_expires_at,
            "reason": safe_reason,
            "source_subscription_id": subscription_id,
            "previous_entitlement": entitlement,
            "previous_subscription_count": len(subscriptions),
            "target_snapshot": snapshot,
            "warnings": warnings,
            "schema_version": 1,
        }
        self._put_override_audit(audit_record)

        try:
            subscription = {
                "subscription_id": subscription_id,
                "user_id": safe_user_id,
                "provider": "admin_grant",
                "tier": legacy_tier_for_plan_code(safe_plan_code),
                "plan_code": safe_plan_code,
                "status": "active",
                "effective_at": created_at,
                "expires_at": safe_expires_at,
                "retention_expires_at": retention_expires_at,
                "product_code": product_code,
                "source_event_id": override_id,
                "source_occurred_at": created_at,
                "management_channel": "admin_override",
                "seat_limit": resolved_seat_limit,
                "updated_at": created_at,
            }
            self._billing_repo.upsert_subscription(subscription)

            organization = {}
            workspace = {}
            membership = {}
            if safe_plan_code in {"studio", "enterprise", "education"}:
                organization_payload = self._provision_admin_team_access(
                    user_id=safe_user_id,
                    email=_safe_str(snapshot.get("email")),
                    username=_safe_str(snapshot.get("username")),
                    plan_code=safe_plan_code,
                    seat_limit=resolved_seat_limit,
                    organization_name=organization_name,
                    subscription=subscription,
                    updated_by_user_id=granted_by_user_id,
                    updated_by_email=granted_by_email,
                )
                organization = organization_payload.get("organization") or {}
                workspace = organization_payload.get("workspace") or {}
                membership = (
                    organization_payload.get("membership")
                    or organization_payload.get("teacher_membership")
                    or {}
                )
                self._ensure_free_entitlement_if_missing(safe_user_id)
            else:
                self._project_personal_entitlement(
                    safe_user_id,
                    subscription,
                    existing_subscriptions=subscriptions,
                    existing_entitlement=entitlement,
                )

            updated_entitlement = self._get_entitlement(safe_user_id, warnings)
            updated_subscriptions = self._list_subscriptions_for_user(safe_user_id, warnings)
            updated_snapshot = self._build_user_record(
                safe_user_id,
                app_profile=app_profile,
                auth_account=auth_account,
                cognito_profile=cognito_profile,
                warnings=warnings,
                entitlement=updated_entitlement,
                subscriptions=updated_subscriptions,
            )
            audit_record.update(
                {
                    "updated_at": _utc_now_iso(),
                    "status": "applied",
                    "organization_id": _safe_str(organization.get("organization_id")),
                    "workspace_id": _safe_str(workspace.get("workspace_id")),
                    "membership_entity_id": _safe_str(membership.get("entity_id")),
                    "resulting_entitlement": updated_entitlement,
                    "result_snapshot": updated_snapshot,
                }
            )
            self._put_override_audit(audit_record)
            return {
                "overridden": True,
                "override_id": override_id,
                "subscription": subscription,
                "organization": organization,
                "workspace": workspace,
                "membership": membership,
                "user": updated_snapshot,
                "warnings": warnings,
            }
        except Exception as exc:
            audit_record.update(
                {
                    "updated_at": _utc_now_iso(),
                    "status": "failed",
                    "error": str(exc),
                }
            )
            self._put_override_audit(audit_record)
            raise

    def delete_user(
        self,
        *,
        user_id: str,
        deleted_by_user_id: str,
        deleted_by_email: str,
        reason: str,
        confirm_email: str,
        force: bool = False,
    ) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        safe_reason = _safe_str(reason)
        safe_confirm_email = _safe_str(confirm_email).lower()
        if not safe_user_id:
            raise ValueError("User ID is required.")
        if not safe_reason:
            raise ValueError("Deletion reason is required.")
        if not safe_confirm_email:
            raise ValueError("The user's login email is required to confirm deletion.")
        if self._tombstones is None:
            raise RuntimeError("User tombstones table is not configured.")
        if self._billing_repo is None:
            raise RuntimeError("Billing repository is not available.")

        warnings: list[str] = []
        app_profile = self._get_user_profile(safe_user_id, warnings)
        auth_account = self._get_auth_account(safe_user_id, warnings)
        cognito_profile = {}
        if not app_profile and not auth_account:
            raise AdminUserNotFoundError("User not found.")

        entitlement = self._get_entitlement(safe_user_id, warnings)
        subscriptions = self._list_subscriptions_for_user(safe_user_id, warnings)
        primary_subscription = choose_primary_subscription(subscriptions) or {}
        customer_links = self._list_customer_link_items(safe_user_id, warnings)
        purchase_tokens = self._list_purchase_tokens(safe_user_id, warnings)

        snapshot = self._build_user_record(
            safe_user_id,
            app_profile=app_profile,
            auth_account=auth_account,
            cognito_profile=cognito_profile,
            warnings=warnings,
            customer_links=customer_links,
            entitlement=entitlement,
            subscriptions=subscriptions,
        )

        expected_email = _safe_str(
            snapshot.get("email")
            or auth_account.get("email")
            or app_profile.get("email")
            or cognito_profile.get("email")
        ).lower()
        if not expected_email:
            raise ValueError("This user does not have a login email available for confirmation.")
        if safe_confirm_email != expected_email:
            raise ValueError("Type the user's login email exactly to confirm deletion.")

        if snapshot["has_active_subscription"] and not force:
            raise AdminDeleteRequiresForceError(
                (
                    "This user still has an active paid subscription. "
                    "Delete again with force enabled only if you mean to remove the account anyway."
                ),
                snapshot=snapshot,
            )

        deleted_at = _utc_now_iso()
        tombstone = {
            "user_id": safe_user_id,
            "deleted_at": deleted_at,
            "deleted_by_user_id": _safe_str(deleted_by_user_id),
            "deleted_by_email": _safe_str(deleted_by_email).lower(),
            "reason": safe_reason,
            "force": bool(force),
            "status": "pending",
            "schema_version": 1,
            "user_snapshot": snapshot,
            "app_profile_snapshot": app_profile,
            "cognito_snapshot": cognito_profile,
            "entitlement_snapshot": entitlement,
            "subscriptions_snapshot": subscriptions,
            "customer_links_snapshot": customer_links,
            "purchase_token_summary": {
                "count": len(purchase_tokens),
                "providers": sorted(
                    {
                        normalize_provider(_safe_str(item.get("provider")))
                        for item in purchase_tokens
                        if _safe_str(item.get("provider"))
                    }
                ),
            },
            "retained_resources": [
                "ai_usage_state",
                "ai_usage_events",
                "posthog_events",
                "future_social_history",
            ],
            "warnings": warnings,
        }
        self._tombstones.put_item(Item=tombstone)

        deleted_resources = {
            "cognito_user": False,
            "users_table_profile": bool(app_profile),
            "username_claim": bool(
                _safe_str(app_profile.get("username_lc") or app_profile.get("username"))
            ),
            "customer_links": len(customer_links),
            "purchase_tokens": len(purchase_tokens),
            "subscriptions": len(subscriptions),
            "entitlement": bool(entitlement),
        }

        try:
            cognito_username = _safe_str(
                cognito_profile.get("username")
                or auth_account.get("legacy_cognito_username")
            )
            if cognito_username:
                self._delete_cognito_user(cognito_username)
                deleted_resources["cognito_user"] = True

            username_lc = _safe_str(
                app_profile.get("username_lc") or app_profile.get("username")
            ).lower() or None
            self._billing_repo.delete_user_account_data(
                safe_user_id,
                username_lc=username_lc,
            )
            self._mark_tombstone(
                user_id=safe_user_id,
                deleted_at=deleted_at,
                status="completed",
                deleted_resources=deleted_resources,
                warnings=warnings,
            )
        except Exception as exc:
            self._mark_tombstone(
                user_id=safe_user_id,
                deleted_at=deleted_at,
                status="failed",
                deleted_resources=deleted_resources,
                warnings=warnings,
                error=str(exc),
            )
            raise

        return {
            "deleted": True,
            "user_id": safe_user_id,
            "deleted_at": deleted_at,
            "tombstone_key": {
                "user_id": safe_user_id,
                "deleted_at": deleted_at,
            },
            "deleted_resources": deleted_resources,
            "retained_resources": tombstone["retained_resources"],
            "user": snapshot,
            "warnings": warnings,
        }

    def _normalize_override_seat_limit(
        self,
        plan_code: str,
        raw_seat_limit: int | None,
        *,
        plan: Dict[str, Any],
    ) -> int:
        limits = plan.get("limits") if isinstance(plan, dict) else {}
        if plan_code == "studio":
            seat_limit = _safe_int(raw_seat_limit) or _safe_int(
                (limits or {}).get("members"),
            ) or 5
            if seat_limit < 5:
                raise ValueError("Studio seat limit must be at least 5.")
            if seat_limit > 5000:
                raise ValueError("Studio seat limit is too large.")
            return seat_limit
        if plan_code == "education":
            return education_seat_limit(
                raw_seat_limit if raw_seat_limit is not None
                else (limits or {}).get("default_seats", 20)
            )
        if plan_code == "enterprise":
            seat_limit = _safe_int(raw_seat_limit) or _safe_int(
                (limits or {}).get("members"),
            ) or 500
            if seat_limit < 1:
                raise ValueError("Enterprise seat limit must be at least 1.")
            if seat_limit > 5000:
                raise ValueError("Enterprise seat limit is too large.")
            return seat_limit
        return 0

    def _put_override_audit(self, record: Dict[str, Any]) -> None:
        if self._entitlement_overrides is None:
            raise RuntimeError("Admin entitlement override audit table is not configured.")
        self._entitlement_overrides.put_item(Item=dict(record))

    def _project_personal_entitlement(
        self,
        user_id: str,
        subscription: Dict[str, Any],
        *,
        existing_subscriptions: list[Dict[str, Any]],
        existing_entitlement: Dict[str, Any],
    ) -> None:
        subscriptions = [
            item
            for item in existing_subscriptions
            if isinstance(item, dict)
            and _safe_str(item.get("subscription_id"))
            != _safe_str(subscription.get("subscription_id"))
            and normalize_plan_code(item.get("plan_code") or item.get("tier")) not in {"studio", "enterprise", "education"}
        ]
        subscriptions.append(subscription)
        primary = choose_primary_subscription(subscriptions)
        revision = int((existing_entitlement or {}).get("revision") or 0) + 1
        if not primary:
            self._billing_repo.put_entitlement(
                free_entitlement(user_id=user_id, revision=revision).to_dict()
            )
            return
        selected_status = subscription_effective_status(primary)
        selected_plan_code = normalize_plan_code(
            primary.get("plan_code") or primary.get("tier") or "free"
        )
        self._billing_repo.put_entitlement(
            {
                "user_id": user_id,
                "tier": legacy_tier_for_plan_code(selected_plan_code),
                "status": selected_status,
                "effective_at": primary.get("effective_at") or _utc_now_iso(),
                "expires_at": primary.get("expires_at"),
                "source_provider": normalize_provider(
                    _safe_str(primary.get("provider") or "unknown")
                ),
                "source_subscription_id": _safe_str(primary.get("subscription_id")),
                "capabilities": entitlement_capabilities_for_status(
                    selected_plan_code,
                    selected_status,
                ),
                "limits": entitlement_limits_for_status(selected_plan_code, selected_status),
                "management_channel": primary.get("management_channel")
                or primary.get("provider")
                or "unknown",
                "plan_code": selected_plan_code,
                "product_code": primary.get("product_code"),
                "source_occurred_at": primary.get("source_occurred_at"),
                "revision": revision,
            }
        )

    def _ensure_free_entitlement_if_missing(self, user_id: str) -> None:
        if self._billing_repo.get_entitlement(user_id):
            return
        self._billing_repo.put_entitlement(free_entitlement(user_id=user_id).to_dict())

    def _provision_admin_team_access(
        self,
        *,
        user_id: str,
        email: str,
        username: str,
        plan_code: str,
        seat_limit: int,
        organization_name: str,
        subscription: Dict[str, Any],
        updated_by_user_id: str,
        updated_by_email: str,
    ) -> Dict[str, Any]:
        organization_id = _stable_admin_org_id(plan_code, user_id)
        fallback_name = (
            f"{_safe_str(username) or _safe_str(email) or user_id} "
            f"{plan_code.title()}"
        )
        name = _safe_str(organization_name) or fallback_name
        if plan_code == "education":
            return self._collaboration_repo.provision_education_organization(
                {
                    "organization_id": organization_id,
                    "teacher_user_id": user_id,
                    "teacher_email": email,
                    "name": name,
                    "seat_limit": seat_limit,
                    "status": "active",
                    "source_provider": "admin_grant",
                    "access_expires_at": subscription.get("expires_at") or "",
                    "source_subscription_id": subscription.get("subscription_id"),
                    "last_active_subscription_id": subscription.get("subscription_id"),
                    "support_notes": "Created by admin entitlement override.",
                    "locked_at": "",
                    "retention_expires_at": "",
                    "archived_at": "",
                    "purge_pending_at": "",
                    "purged_at": "",
                },
                updated_by_user_id=updated_by_user_id,
                updated_by_email=updated_by_email,
            )

        organization = self._collaboration_repo.save_organization(
            {
                "organization_id": organization_id,
                "name": name,
                "status": "active",
                "plan_code": plan_code,
                "seat_limit": seat_limit,
                "owner_user_id": user_id,
                "source_provider": "admin_grant",
                "access_expires_at": subscription.get("expires_at") or "",
                "source_subscription_id": subscription.get("subscription_id"),
                "last_active_subscription_id": subscription.get("subscription_id"),
                "shared_workspace_enabled": True,
                "support_notes": "Created by admin entitlement override.",
                "locked_at": "",
                "retention_expires_at": "",
                "archived_at": "",
                "purge_pending_at": "",
                "purged_at": "",
            },
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        workspace = self._collaboration_repo.save_workspace(
            {
                "workspace_id": f"{organization_id}-shared",
                "organization_id": organization_id,
                "owner_user_id": user_id,
                "name": f"{name} Shared Cloud",
                "visibility": "organization",
                "default_project_privacy": "workspace",
                "status": "active",
            },
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        membership = self._collaboration_repo.save_membership(
            {
                "organization_id": organization_id,
                "user_id": user_id,
                "email": email,
                "role": "owner",
                "status": "active",
                "seat_consumed": True,
            },
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        return {
            "organization": organization,
            "workspace": workspace,
            "membership": membership,
        }

    def _build_user_record(
        self,
        user_id: str,
        *,
        app_profile: Dict[str, Any],
        auth_account: Dict[str, Any],
        cognito_profile: Dict[str, Any],
        ai_usage_state: Dict[str, Any] | None = None,
        warnings: list[str],
        customer_links: list[Dict[str, Any]] | None = None,
        entitlement: Dict[str, Any] | None = None,
        subscriptions: list[Dict[str, Any]] | None = None,
    ) -> Dict[str, Any]:
        app_profile = app_profile or {}
        cognito_profile = cognito_profile or {}
        ai_usage_state = (
            ai_usage_state
            if ai_usage_state is not None
            else self._get_ai_usage_state(user_id, warnings)
        ) or {}
        entitlement = entitlement if entitlement is not None else self._get_entitlement(
            user_id, warnings
        )
        subscriptions = (
            subscriptions
            if subscriptions is not None
            else self._list_subscriptions_for_user(user_id, warnings)
        )
        customer_links = (
            customer_links
            if customer_links is not None
            else self._list_customer_link_items(user_id, warnings)
        )
        primary_subscription = choose_primary_subscription(subscriptions) or {}
        auth_account = auth_account or {}
        auth_sessions = self._list_auth_sessions_for_user(user_id, warnings)
        session_summary = self._summarize_auth_sessions(auth_sessions)

        email = _safe_str(
            auth_account.get("email")
            or app_profile.get("email")
            or cognito_profile.get("email")
        )
        username = _safe_str(app_profile.get("username"))
        display_name = _safe_str(
            app_profile.get("display_name") or cognito_profile.get("display_name")
        )
        auth_provider = _safe_str(
            auth_account.get("auth_provider")
            or app_profile.get("auth_provider")
            or cognito_profile.get("auth_provider")
        ) or "email"
        auth_source = self._auth_source(auth_account, cognito_profile)
        auth_status = self._auth_status(auth_source, cognito_profile)

        linked_providers = {
            normalize_provider(_safe_str(item.get("provider")))
            for item in customer_links
            if _safe_str(item.get("provider"))
        }
        if auth_provider:
            linked_providers.add(normalize_provider(auth_provider))
        linked_providers.discard("unknown")

        created_at = _safe_str(
            app_profile.get("created_at") or cognito_profile.get("created_at")
        )
        updated_at = _safe_str(
            app_profile.get("updated_at") or cognito_profile.get("updated_at")
        )
        last_seen_at = _safe_str(
            app_profile.get("last_seen_at")
            or app_profile.get("updated_at")
            or cognito_profile.get("updated_at")
            or created_at
        )

        subscription_plan_code = normalize_plan_code(
            _safe_str(entitlement.get("plan_code") or primary_subscription.get("plan_code"))
        )
        subscription_status = normalize_status(
            _safe_str(entitlement.get("status") or primary_subscription.get("status"))
        )
        subscription_provider = normalize_provider(
            _safe_str(
                entitlement.get("source_provider") or primary_subscription.get("provider")
            )
        )
        has_active_subscription = (
            subscription_plan_code != "free"
            and status_has_active_access(subscription_status)
        )
        catalog_repo = getattr(self, "_catalog_repo", BillingCatalogRepository())
        collaboration_repo = getattr(
            self,
            "_collaboration_repo",
            CollaborationRepository(),
        )
        plan_code = infer_plan_code(_safe_str(entitlement.get("plan_code"))) if _safe_str(entitlement.get("plan_code")) else subscription_plan_code
        plan = catalog_plan_by_code(
            plan_code,
            catalog=catalog_repo.get_catalog(),
        )
        collaboration_summary = (
            collaboration_repo.build_user_access_snapshot(user_id).get("summary") or {}
            if collaboration_repo.is_configured()
            else {}
        )

        return {
            "user_id": user_id,
            "email": email,
            "username": username or None,
            "display_name": display_name,
            "given_name": _safe_str(
                app_profile.get("given_name") or cognito_profile.get("given_name")
            ),
            "family_name": _safe_str(
                app_profile.get("family_name") or cognito_profile.get("family_name")
            ),
            "music_profile": _safe_str(app_profile.get("music_profile")),
            "email_verified": bool(
                auth_account.get("email_verified")
                if "email_verified" in auth_account
                else app_profile.get("email_verified")
                if "email_verified" in app_profile
                else cognito_profile.get("email_verified")
            ),
            "auth_provider": auth_provider,
            "auth_source": auth_source,
            "auth_status": auth_status,
            "linked_providers": sorted(linked_providers),
            "profile_status": _safe_str(app_profile.get("profile_status") or "active"),
            "onboarding_state": _safe_str(app_profile.get("onboarding_state")),
            "birthdate": _safe_str(app_profile.get("birthdate")),
            "account_enabled": bool(auth_account) or bool(
                cognito_profile.get("account_enabled")
                if "account_enabled" in cognito_profile
                else True
            ),
            "cognito_username": _safe_str(
                app_profile.get("cognito_username") or cognito_profile.get("username")
            ),
            "native_auth_exists": bool(auth_account),
            "native_auth_provider": _safe_str(auth_account.get("auth_provider")),
            "native_email_verified": bool(auth_account.get("email_verified")),
            "native_session_count": session_summary["session_count"],
            "native_active_session_count": session_summary["active_session_count"],
            "native_last_session_created_at": session_summary["last_session_created_at"],
            "native_last_session_expires_at": session_summary["last_session_expires_at"],
            "legacy_cognito_enabled": bool(auth_account.get("legacy_cognito_enabled")),
            "legacy_cognito_username": _safe_str(
                auth_account.get("legacy_cognito_username")
                or app_profile.get("cognito_username")
                or cognito_profile.get("username")
            ),
            "legacy_cognito_migrated_at": _safe_str(
                auth_account.get("legacy_cognito_migrated_at")
            ),
            "legacy_auth_status": _safe_str(cognito_profile.get("auth_status")),
            "subscription_tier": subscription_plan_code,
            "subscription_status": subscription_status,
            "subscription_provider": subscription_provider,
            "has_active_subscription": has_active_subscription,
            "subscription_count": len(subscriptions),
            "plan_code": _safe_str(plan.get("code")),
            "plan_label": _safe_str(plan.get("label")),
            "plan_group": _safe_str(plan.get("group")),
            "organization_count": _safe_int(
                collaboration_summary.get("organization_count")
            ),
            "workspace_count": _safe_int(
                collaboration_summary.get("workspace_count")
            ),
            "cloud_project_count": _safe_int(
                collaboration_summary.get("cloud_project_count")
            ),
            "ai_credits_used_today": _safe_int(ai_usage_state.get("ai_credits_used_today")),
            "ai_tokens_used_month": _safe_int(ai_usage_state.get("ai_tokens_used_month")),
            "ai_prompts_used_today": _safe_int(ai_usage_state.get("ai_prompts_used_today")),
            "ai_prompts_used_week": _safe_int(ai_usage_state.get("ai_prompts_used_week")),
            "admin_prompt_grants_total": _safe_int(
                ai_usage_state.get("admin_prompt_grants_total")
            ),
            "admin_prompt_grants_remaining": _safe_int(
                ai_usage_state.get("admin_prompt_grants_remaining")
            ),
            "admin_prompt_grants_updated_at": _safe_str(
                ai_usage_state.get("admin_prompt_grants_updated_at")
            ),
            "admin_prompt_grants_updated_by": _safe_str(
                ai_usage_state.get("admin_prompt_grants_updated_by")
            ),
            "admin_prompt_grants_updated_email": _safe_str(
                ai_usage_state.get("admin_prompt_grants_updated_email")
            ),
            "created_at": created_at,
            "updated_at": updated_at,
            "last_seen_at": last_seen_at,
            "customer_link_count": len(customer_links),
            "customer_link_updated_at": self._latest_linked_at(customer_links),
            "deleted_at": "",
            "notes": [],
        }

    def _matches_query(self, record: Dict[str, Any], query: str) -> bool:
        haystacks = [
            record.get("user_id"),
            record.get("email"),
            record.get("username"),
            record.get("display_name"),
            record.get("given_name"),
            record.get("family_name"),
            record.get("cognito_username"),
            record.get("legacy_cognito_username"),
            record.get("auth_provider"),
            record.get("auth_source"),
            record.get("auth_status"),
        ]
        return any(query in _normalize_query(value) for value in haystacks if value)

    def _load_user_record(
        self,
        user_id: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        if not safe_user_id:
            return {}
        app_profile = self._get_user_profile(safe_user_id, warnings)
        auth_account = self._get_auth_account(safe_user_id, warnings)
        cognito_profile = {}
        ai_usage_state = self._get_ai_usage_state(safe_user_id, warnings)
        if not app_profile and not auth_account and not ai_usage_state:
            return {}
        return self._build_user_record(
            safe_user_id,
            app_profile=app_profile,
            auth_account=auth_account,
            cognito_profile=cognito_profile,
            ai_usage_state=ai_usage_state,
            warnings=warnings,
        )

    def _search_candidate_user_ids(
        self,
        query: str,
        *,
        limit: int,
        warnings: list[str],
    ) -> list[str]:
        user_ids: list[str] = []
        seen: set[str] = set()

        def push(candidate: str) -> None:
            safe = _safe_str(candidate)
            if not safe or safe in seen:
                return
            seen.add(safe)
            user_ids.append(safe)

        app_profile = self._get_user_profile(query, warnings)
        if app_profile:
            push(_safe_str(app_profile.get("user_id")))

        username_profile = self._get_user_profile_by_username(query, warnings)
        if username_profile:
            push(_safe_str(username_profile.get("user_id")))

        if "@" in query:
            email_profile = self._get_user_profile_by_email(query, warnings)
            if email_profile:
                push(_safe_str(email_profile.get("user_id")))
            auth_account = self._get_auth_account_by_email(query, warnings)
            if auth_account:
                push(_safe_str(auth_account.get("user_id")))
        if not user_ids:
            for user_id in self._fallback_recent_user_ids(limit=max(limit * 3, 50), warnings=warnings):
                push(user_id)
                if len(user_ids) >= max(limit * 3, 50):
                    break
        return user_ids

    def _list_recent_candidate_user_ids(
        self,
        *,
        limit: int,
        warnings: list[str],
    ) -> list[str]:
        result: list[str] = []
        seen: set[str] = set()
        for user_id in self._fallback_recent_user_ids(limit=max(limit * 2, 50), warnings=warnings):
            safe = _safe_str(user_id)
            if not safe or safe in seen:
                continue
            seen.add(safe)
            result.append(safe)
            if len(result) >= max(limit * 2, 50):
                break
        return result

    def _list_subscription_candidate_user_ids(
        self,
        subscription_filter: str,
        *,
        warnings: list[str],
    ) -> list[str]:
        if self._entitlements is None:
            return []

        normalized_filter = _normalize_subscription_filter(subscription_filter)
        if normalized_filter == "all":
            return []

        result: list[str] = []
        seen: set[str] = set()
        start_key = None
        while True:
            try:
                kwargs: dict[str, Any] = {
                    "ProjectionExpression": (
                        "user_id, plan_code, #status, source_provider"
                    ),
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(
                    f"subscription_filter_unavailable:{exc.__class__.__name__}"
                )
                return result

            for item in response.get("Items", []):
                user_id = _safe_str(item.get("user_id"))
                plan_code = normalize_plan_code(item.get("plan_code") or "free")
                status = normalize_status(_safe_str(item.get("status")))
                provider = normalize_provider(_safe_str(item.get("source_provider")))
                if (
                    not user_id
                    or user_id in seen
                    or plan_code == "free"
                    or not status_has_active_access(status)
                ):
                    continue

                is_match = (
                    provider == "admin_grant"
                    if normalized_filter == "granted"
                    else provider not in {"admin_grant", "unknown"}
                    and status != "trialing"
                )
                if is_match:
                    seen.add(user_id)
                    result.append(user_id)

            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break
        return result

    def _fallback_recent_user_ids(
        self,
        *,
        limit: int,
        warnings: list[str],
    ) -> list[str]:
        profiles = self._list_recent_app_profiles(limit=limit, warnings=warnings)
        result = [
            _safe_str(item.get("user_id"))
            for item in profiles
            if _safe_str(item.get("user_id"))
        ]
        return result

    def _list_recent_app_profiles(
        self,
        *,
        limit: int,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            return self._billing_repo.list_recent_user_profiles(limit=limit)
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"users_table_unavailable:{exc.__class__.__name__}")
            return []

    def _get_user_profile_by_username(
        self,
        username: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        if self._billing_repo is None:
            return {}
        try:
            return self._billing_repo.get_user_profile_by_username(username) or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"username_profile_unavailable:{exc.__class__.__name__}")
            return {}

    def _get_user_profile_by_email(
        self,
        email: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        if self._billing_repo is None:
            return {}
        try:
            return self._billing_repo.get_user_profile_by_email(email) or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"user_email_index_unavailable:{exc.__class__.__name__}")
            return {}

    def _get_auth_account(
        self,
        user_id: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        if self._billing_repo is None:
            return {}
        try:
            return self._billing_repo.get_auth_account(user_id) or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"auth_account_unavailable:{exc.__class__.__name__}")
            return {}

    def _get_auth_account_by_email(
        self,
        email: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        if self._billing_repo is None:
            return {}
        try:
            return self._billing_repo.get_auth_account_by_email(email) or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"auth_email_index_unavailable:{exc.__class__.__name__}")
            return {}

    def _list_auth_sessions_for_user(
        self,
        user_id: str,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            return self._billing_repo.list_auth_sessions_for_user(user_id) or []
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"auth_sessions_unavailable:{exc.__class__.__name__}")
            return []

    def _get_cognito_profile_for_user_id(
        self,
        user_id: str,
        warnings: list[str],
    ) -> Dict[str, Any]:
        if self._cognito is None or not config.COGNITO_USER_POOL_ID:
            return {}
        try:
            response = self._cognito.list_users(
                UserPoolId=config.COGNITO_USER_POOL_ID,
                Filter=f'sub = "{user_id}"',
                Limit=1,
            )
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"cognito_users_unavailable:{exc.__class__.__name__}")
            return {}
        users = response.get("Users") or []
        if not users:
            return {}
        return self._cognito_user_to_profile(users[0])

    def _cognito_user_to_profile(self, user: Dict[str, Any]) -> Dict[str, Any]:
        attributes = {
            _safe_str(item.get("Name")): _safe_str(item.get("Value"))
            for item in user.get("Attributes", [])
            if _safe_str(item.get("Name"))
        }
        user_id = _safe_str(attributes.get("sub"))
        if not user_id:
            return {}
        display_name = _safe_str(attributes.get("name"))
        if not display_name:
            display_name = " ".join(
                part
                for part in (
                    _safe_str(attributes.get("given_name")),
                    _safe_str(attributes.get("family_name")),
                )
                if part
            ).strip()
        return {
            "user_id": user_id,
            "username": _safe_str(user.get("Username")),
            "email": _safe_str(attributes.get("email")),
            "display_name": display_name,
            "given_name": _safe_str(attributes.get("given_name")),
            "family_name": _safe_str(attributes.get("family_name")),
            "email_verified": _safe_bool(attributes.get("email_verified")),
            "auth_status": _safe_str(user.get("UserStatus")),
            "account_enabled": bool(user.get("Enabled", False)),
            "created_at": _datetime_to_iso(user.get("UserCreateDate")),
            "updated_at": _datetime_to_iso(user.get("UserLastModifiedDate")),
            "auth_provider": "email",
        }


    def _auth_source(
        self,
        auth_account: Dict[str, Any],
        cognito_profile: Dict[str, Any],
    ) -> str:
        if auth_account:
            if bool(auth_account.get("legacy_cognito_enabled")):
                return "native_legacy_bridge"
            return "native"
        if cognito_profile:
            return "legacy_cognito_only"
        return "unknown"

    def _auth_status(
        self,
        auth_source: str,
        cognito_profile: Dict[str, Any],
    ) -> str:
        if auth_source == "native":
            return "native_active"
        if auth_source == "native_legacy_bridge":
            return "native_legacy_bridge"
        if auth_source == "legacy_cognito_only":
            return _safe_str(cognito_profile.get("auth_status") or "legacy_cognito_only")
        return "unknown"

    def _summarize_auth_sessions(
        self,
        sessions: list[Dict[str, Any]],
    ) -> Dict[str, Any]:
        active_session_count = 0
        last_created_at = ""
        last_expires_at = ""
        now = datetime.now(timezone.utc)

        for session in sessions:
            if not isinstance(session, dict):
                continue
            created_at = _safe_str(session.get("created_at"))
            expires_at = _safe_str(session.get("expires_at"))
            last_created_at = _later_iso(last_created_at, created_at)
            last_expires_at = _later_iso(last_expires_at, expires_at)
            expires_dt = _parse_iso(expires_at)
            if expires_dt is not None and expires_dt > now:
                active_session_count += 1

        return {
            "session_count": len([item for item in sessions if isinstance(item, dict)]),
            "active_session_count": active_session_count,
            "last_session_created_at": last_created_at,
            "last_session_expires_at": last_expires_at,
        }

    def _get_user_profile(self, user_id: str, warnings: list[str]) -> Dict[str, Any]:
        if self._users is None:
            return {}
        try:
            return self._users.get_item(Key={"user_id": user_id}).get("Item") or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"user_profile_unavailable:{exc.__class__.__name__}")
            return {}

    def _get_entitlement(self, user_id: str, warnings: list[str]) -> Dict[str, Any]:
        if self._entitlements is None:
            return {}
        try:
            return self._entitlements.get_item(Key={"user_id": user_id}).get("Item") or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"entitlement_unavailable:{exc.__class__.__name__}")
            return {}

    def _get_ai_usage_state(self, user_id: str, warnings: list[str]) -> Dict[str, Any]:
        if self._ai_usage_state is None:
            return {}
        try:
            return self._ai_usage_state.get_item(Key={"user_id": user_id}).get("Item") or {}
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"ai_usage_state_unavailable:{exc.__class__.__name__}")
            return {}

    def _list_subscriptions_for_user(
        self,
        user_id: str,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            subscriptions = self._billing_repo.list_subscriptions_for_user(user_id)
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"subscriptions_unavailable:{exc.__class__.__name__}")
            return []

        return [
            {
                "subscription_id": _safe_str(item.get("subscription_id")),
                "plan_code": normalize_plan_code(_safe_str(item.get("plan_code"))),
                "status": normalize_status(_safe_str(item.get("status"))),
                "provider": normalize_provider(_safe_str(item.get("provider"))),
                "effective_at": _safe_str(item.get("effective_at")),
                "expires_at": _safe_str(item.get("expires_at")),
                "updated_at": _safe_str(item.get("updated_at")),
            }
            for item in subscriptions
            if isinstance(item, dict)
        ]

    def _list_customer_link_items(
        self,
        user_id: str,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            response_items = self._billing_repo.list_customer_links_for_user(user_id)
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"customer_links_unavailable:{exc.__class__.__name__}")
            return []
        return [
            {
                "provider": normalize_provider(_safe_str(item.get("provider"))),
                "customer_key": _safe_str(item.get("customer_key")),
                "updated_at": _safe_str(item.get("updated_at")),
            }
            for item in response_items
            if isinstance(item, dict)
        ]

    def _list_purchase_tokens(
        self,
        user_id: str,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            response_items = self._billing_repo.list_purchase_tokens_for_user(user_id)
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"purchase_tokens_unavailable:{exc.__class__.__name__}")
            return []
        return [
            {
                "provider": normalize_provider(_safe_str(item.get("provider"))),
                "updated_at": _safe_str(item.get("updated_at")),
            }
            for item in response_items
            if isinstance(item, dict)
        ]

    def _latest_linked_at(self, customer_links: list[Dict[str, Any]]) -> str:
        latest = ""
        for item in customer_links:
            latest = _later_iso(latest, _safe_str(item.get("updated_at")))
        return latest

    def _delete_cognito_user(self, cognito_username: str) -> None:
        if self._cognito is None or not config.COGNITO_USER_POOL_ID:
            return
        try:
            self._cognito.admin_delete_user(
                UserPoolId=config.COGNITO_USER_POOL_ID,
                Username=cognito_username,
            )
        except ClientError as exc:
            code = _safe_str(exc.response.get("Error", {}).get("Code"))
            if code == "UserNotFoundException":
                return
            raise

    def _mark_tombstone(
        self,
        *,
        user_id: str,
        deleted_at: str,
        status: str,
        deleted_resources: Dict[str, Any],
        warnings: list[str],
        error: str = "",
    ) -> None:
        if self._tombstones is None:
            return
        self._tombstones.update_item(
            Key={"user_id": user_id, "deleted_at": deleted_at},
            UpdateExpression=(
                "SET #status = :status, deletion_completed_at = :completed_at, "
                "deleted_resources = :deleted_resources, warnings = :warnings, last_error = :last_error"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":status": status,
                ":completed_at": _utc_now_iso(),
                ":deleted_resources": deleted_resources,
                ":warnings": warnings,
                ":last_error": error,
            },
        )
