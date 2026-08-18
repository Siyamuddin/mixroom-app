from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from typing import Any, Dict
from uuid import uuid4

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from boto3.dynamodb.conditions import Attr, Key
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    Attr = None
    Key = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import config
from .cloud_object_storage import (
    cloud_project_storage_mode,
    cloud_project_storage_provider,
    copy_object_extra_args,
    create_cloud_project_object_client,
    legacy_cloud_project_storage_mode,
    put_object_extra_args,
    supports_object_versions,
    upload_headers,
)

_ORG_STATUSES = frozenset(
    {"draft", "active", "past_due", "locked", "suspended", "archived", "purge_pending", "purged"}
)
_MEMBERSHIP_STATUSES = frozenset({"pending", "active", "inactive", "revoked", "removed"})
_MEMBERSHIP_ROLES = frozenset(
    {"owner", "admin", "manager", "teacher", "student", "member", "viewer"}
)
_RESERVED_SEAT_STATUSES = frozenset({"pending", "active"})
_EDUCATION_SEAT_OPTIONS = (10, 20, 30)
_WORKSPACE_STATUSES = frozenset({"active", "locked", "archived"})
_PROJECT_STATUSES = frozenset({"draft", "active", "archived", "purge_pending", "purged"})
_ORG_READ_STATUSES = frozenset({"active", "past_due", "locked", "suspended"})
_ORG_WRITE_STATUSES = frozenset({"active", "past_due"})
_WORKSPACE_READ_STATUSES = frozenset({"active", "locked"})
_WORKSPACE_WRITE_STATUSES = frozenset({"active"})
_PRIVATE_ACCESS_VALUES = frozenset({"private", "owner", "personal", "invite_only"})
_WRITE_ACCESS_ROLES = frozenset({"owner", "admin", "manager", "member"})
_WORKSPACE_CREATE_ROLES = frozenset(
    {"owner", "admin", "manager", "teacher", "student", "member"}
)
_SAFE_ID_RE = re.compile(r"[^a-zA-Z0-9_.=-]+")
_MIXROOM_CONTENT_TYPE = "application/octet-stream"
_CLOUD_BUNDLE_STORAGE_MODES = frozenset(
    {cloud_project_storage_mode(), legacy_cloud_project_storage_mode()}
)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


def _payload_or_current_str(
    payload: Dict[str, Any],
    current: Dict[str, Any],
    key: str,
    *,
    default: str = "",
) -> str:
    if key in payload:
        return _safe_str(payload.get(key))
    return _safe_str(current.get(key)) or default


def _safe_email(value: Any) -> str:
    return _safe_str(value).lower()


def _safe_bool(value: Any, *, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    normalized = _safe_str(value).lower()
    if normalized in {"true", "1", "yes", "on"}:
        return True
    if normalized in {"false", "0", "no", "off"}:
        return False
    return default


def _safe_int(value: Any, *, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, str):
        normalized = value.strip()
        if not normalized:
            return None
        value = normalized
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _safe_object_component(value: Any, *, fallback: str = "") -> str:
    cleaned = _SAFE_ID_RE.sub("-", _safe_str(value)).strip("-._")
    return cleaned[:120] or fallback


def _coerce_json_document(value: Any) -> Dict[str, Any] | None:
    if value is None:
        return None
    if isinstance(value, dict):
        return value
    raise ValueError("Cloud project document must be a JSON object.")


def _invite_user_id(email: str) -> str:
    digest = hashlib.sha1(_safe_email(email).encode("utf-8")).hexdigest()
    return f"invite:{digest[:24]}"


def _seat_reserved(membership: Dict[str, Any]) -> bool:
    return (
        _safe_str(membership.get("status")).lower() in _RESERVED_SEAT_STATUSES
        and _safe_bool(membership.get("seat_consumed"), default=False)
    )


def _is_cloud_project_bundle(project: Dict[str, Any]) -> bool:
    return _safe_str(project.get("storage_mode")) in _CLOUD_BUNDLE_STORAGE_MODES


def _org_allows_read(organization: Dict[str, Any]) -> bool:
    return _safe_str(organization.get("status") or "active").lower() in _ORG_READ_STATUSES


def _org_allows_write(organization: Dict[str, Any]) -> bool:
    return _safe_str(organization.get("status") or "active").lower() in _ORG_WRITE_STATUSES


def _workspace_allows_read(workspace: Dict[str, Any]) -> bool:
    return _safe_str(workspace.get("status") or "active").lower() in _WORKSPACE_READ_STATUSES


def _workspace_allows_write(workspace: Dict[str, Any]) -> bool:
    return _safe_str(workspace.get("status") or "active").lower() in _WORKSPACE_WRITE_STATUSES


class CollaborationRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._s3 = None
        self._table = None
        if self._ddb is not None and config.COLLABORATION_TABLE:
            self._table = self._ddb.Table(config.COLLABORATION_TABLE)

    def is_configured(self) -> bool:
        return self._table is not None

    def _object_client(self) -> Any:
        if self._s3 is None:
            self._s3 = create_cloud_project_object_client()
        return self._s3

    def list_organizations(self) -> list[Dict[str, Any]]:
        return [
            self._with_organization_seat_summary(item)
            for item in self._list_by_entity_type("organization")
        ]

    def get_organization(self, organization_id: str) -> Dict[str, Any]:
        entity_id = self._entity_id("organization", organization_id)
        return self._with_organization_seat_summary(self._get_item(entity_id))

    def save_organization(
        self,
        payload: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        organization_id = _safe_str(payload.get("organization_id")) or uuid4().hex
        current = self.get_organization(organization_id) or {}
        status = _payload_or_current_str(payload, current, "status", default="active").lower() or "active"
        if status not in _ORG_STATUSES:
            raise ValueError("Organization status is invalid.")
        plan_code = _safe_str(
            payload.get("plan_code") or current.get("plan_code") or "studio"
        ).lower()
        seat_limit = _safe_int(
            payload.get("seat_limit"),
            default=_safe_int(
                current.get("seat_limit"),
                default=20 if plan_code == "education" else 0,
            ),
        )
        if seat_limit < 0:
            raise ValueError("Organization seat limit is invalid.")
        current_seats = self._organization_seat_summary(organization_id)
        if seat_limit > 0 and current_seats["used"] > seat_limit:
            raise ValueError("Seat limit cannot be lower than seats currently used.")
        seat_options = (
            list(_EDUCATION_SEAT_OPTIONS)
            if plan_code == "education"
            else current.get("seat_options") or []
        )
        now = _utc_now_iso()
        shared_workspace_enabled = (
            _safe_bool(
                payload.get("shared_workspace_enabled"),
                # Education organizations have a dedicated class cloud. It is
                # a real workspace so it can be selected separately from a
                # student's personal cloud storage.
                default=True if plan_code == "education" else _safe_bool(
                    current.get("shared_workspace_enabled"), default=True
                ),
            )
        )
        record = {
            "entity_id": self._entity_id("organization", organization_id),
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": _payload_or_current_str(payload, current, "name", default=organization_id),
            "status": status,
            "plan_code": plan_code,
            "seat_limit": seat_limit,
            "seat_options": seat_options,
            "education_admin_enabled": plan_code == "education",
            "teacher_mode_enabled": plan_code == "education",
            "shared_workspace_enabled": shared_workspace_enabled,
            "support_notes": _safe_str(payload.get("support_notes") or current.get("support_notes")),
            "owner_user_id": _payload_or_current_str(payload, current, "owner_user_id"),
            "billing_customer_id": _payload_or_current_str(payload, current, "billing_customer_id"),
            "source_provider": _payload_or_current_str(payload, current, "source_provider"),
            "source_subscription_id": _payload_or_current_str(payload, current, "source_subscription_id"),
            "last_active_subscription_id": _payload_or_current_str(payload, current, "last_active_subscription_id"),
            "locked_at": _payload_or_current_str(payload, current, "locked_at"),
            "retention_expires_at": _payload_or_current_str(payload, current, "retention_expires_at"),
            "archived_at": _payload_or_current_str(payload, current, "archived_at"),
            "purge_pending_at": _payload_or_current_str(payload, current, "purge_pending_at"),
            "purged_at": _payload_or_current_str(payload, current, "purged_at"),
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_str(updated_by_email).lower(),
        }
        self._table.put_item(Item=record)
        return self._with_organization_seat_summary(record)

    def transition_organization_lifecycle(
        self,
        organization_id: str,
        status: str,
        *,
        retention_expires_at: str = "",
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        safe_organization_id = _safe_str(organization_id)
        normalized_status = _safe_str(status).lower()
        if not safe_organization_id:
            raise ValueError("Organization ID is required.")
        if normalized_status not in _ORG_STATUSES:
            raise ValueError("Organization status is invalid.")
        current = self.get_organization(safe_organization_id)
        if not current:
            raise ValueError("Organization not found.")
        now = _utc_now_iso()
        record = {
            **current,
            "status": normalized_status,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_email(updated_by_email),
        }
        if normalized_status in {"locked", "suspended"}:
            record["locked_at"] = _safe_str(record.get("locked_at")) or now
            if retention_expires_at:
                record["retention_expires_at"] = _safe_str(retention_expires_at)
        elif normalized_status == "active":
            record["locked_at"] = ""
            record["archived_at"] = ""
            record["purge_pending_at"] = ""
            record["purged_at"] = ""
            record["retention_expires_at"] = ""
        elif normalized_status == "archived":
            record["archived_at"] = _safe_str(record.get("archived_at")) or now
        elif normalized_status == "purge_pending":
            record["purge_pending_at"] = _safe_str(record.get("purge_pending_at")) or now
        elif normalized_status == "purged":
            record["purged_at"] = _safe_str(record.get("purged_at")) or now
        for derived_key in (
            "seats_active",
            "seats_invited",
            "seats_used",
            "seats_available",
        ):
            record.pop(derived_key, None)
        self._table.put_item(Item=record)
        return self._with_organization_seat_summary(record)

    def lock_organization(
        self,
        organization_id: str,
        *,
        retention_expires_at: str = "",
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        return self.transition_organization_lifecycle(
            organization_id,
            "locked",
            retention_expires_at=retention_expires_at,
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )

    def reactivate_organization(
        self,
        organization_id: str,
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        return self.transition_organization_lifecycle(
            organization_id,
            "active",
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )

    def sync_organization_for_subscription(
        self,
        subscription: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        plan_code = _safe_str(subscription.get("plan_code") or subscription.get("tier")).lower()
        if plan_code not in {"studio", "enterprise", "education"}:
            return {}
        organization = self._linked_organization_for_subscription(subscription)
        if not organization:
            return {}
        subscription_id = _safe_str(subscription.get("subscription_id"))
        status = _safe_str(subscription.get("status")).lower()
        active = status in {"trialing", "active", "grace_period"}
        next_status = "active" if active else "locked"
        payload = {
            "organization_id": organization.get("organization_id"),
            "status": next_status,
            "name": organization.get("name"),
            "plan_code": plan_code,
            "seat_limit": organization.get("seat_limit"),
            "source_provider": subscription.get("provider") or organization.get("source_provider"),
            "source_subscription_id": subscription_id
            or organization.get("source_subscription_id"),
            "last_active_subscription_id": subscription_id
            if active and subscription_id
            else organization.get("last_active_subscription_id"),
            "billing_customer_id": subscription.get("customer_id")
            or subscription.get("billing_customer_id")
            or organization.get("billing_customer_id"),
            "owner_user_id": organization.get("owner_user_id")
            or subscription.get("user_id"),
        }
        if active:
            payload.update(
                {
                    "locked_at": "",
                    "retention_expires_at": "",
                    "archived_at": "",
                    "purge_pending_at": "",
                    "purged_at": "",
                }
            )
            return self.save_organization(
                payload,
                updated_by_user_id=updated_by_user_id,
                updated_by_email=updated_by_email,
            )
        payload["retention_expires_at"] = (
            _safe_str(organization.get("retention_expires_at"))
            or _safe_str(subscription.get("retention_expires_at"))
            or _safe_str(subscription.get("expires_at"))
        )
        locked = self.save_organization(
            payload,
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        if not _safe_str(locked.get("locked_at")):
            locked = self.lock_organization(
                _safe_str(locked.get("organization_id")),
                retention_expires_at=_safe_str(locked.get("retention_expires_at")),
                updated_by_user_id=updated_by_user_id,
                updated_by_email=updated_by_email,
            )
        return locked

    def _linked_organization_for_subscription(
        self,
        subscription: Dict[str, Any],
    ) -> Dict[str, Any]:
        subscription_id = _safe_str(subscription.get("subscription_id"))
        customer_id = _safe_str(
            subscription.get("customer_id") or subscription.get("billing_customer_id")
        )
        if not subscription_id and not customer_id:
            return {}
        for organization in self.list_organizations():
            if subscription_id and subscription_id in {
                _safe_str(organization.get("source_subscription_id")),
                _safe_str(organization.get("last_active_subscription_id")),
            }:
                return organization
            if customer_id and customer_id == _safe_str(organization.get("billing_customer_id")):
                return organization
        return {}

    def purge_organization_cloud_storage(
        self,
        organization_id: str,
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        safe_organization_id = _safe_str(organization_id)
        if not safe_organization_id:
            raise ValueError("Organization ID is required.")
        organization = self.get_organization(safe_organization_id)
        if not organization:
            raise ValueError("Organization not found.")
        for project in self.list_cloud_projects(organization_id=safe_organization_id):
            if not _is_cloud_project_bundle(project):
                continue
            bucket = _safe_str(project.get("document_bucket"))
            keys = {
                _safe_str(project.get("document_key")),
                _safe_str(project.get("pending_upload_key")),
            }
            if bucket and self._object_client() is not None:
                for key in keys:
                    if key:
                        self._delete_s3_key_versions(bucket, key)
            entity_id = _safe_str(project.get("entity_id"))
            if entity_id:
                self._table.delete_item(Key={"entity_id": entity_id})
        return self.transition_organization_lifecycle(
            safe_organization_id,
            "purged",
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )

    def provision_education_organization(
        self,
        payload: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        teacher_user_id = _safe_str(payload.get("teacher_user_id"))
        teacher_email = _safe_email(payload.get("teacher_email"))
        if not teacher_user_id:
            raise ValueError("Teacher user ID is required.")
        seat_limit = _safe_int(payload.get("seat_limit"), default=20)
        if seat_limit not in _EDUCATION_SEAT_OPTIONS:
            raise ValueError("Education seat limit must be 10, 20, or 30.")

        organization = self.save_organization(
            {
                **payload,
                "plan_code": "education",
                "seat_limit": seat_limit,
                "status": _safe_str(payload.get("status") or "active") or "active",
                "shared_workspace_enabled": True,
            },
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        organization_id = _safe_str(organization.get("organization_id"))
        teacher_membership = self.save_membership(
            {
                "organization_id": organization_id,
                "user_id": teacher_user_id,
                "email": teacher_email,
                "role": "teacher",
                "status": "active",
                "seat_consumed": False,
            },
            updated_by_user_id=updated_by_user_id,
            updated_by_email=updated_by_email,
        )
        workspace = self.ensure_education_cloud_workspace(organization)
        return {
            "organization": self.get_organization(organization_id),
            "teacher_membership": teacher_membership,
            "workspace": workspace,
        }

    def ensure_education_cloud_workspace(
        self,
        organization: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Return the stable class-cloud workspace for an education org.

        Older education organizations were provisioned before education cloud
        storage became a selectable destination, so create the missing
        workspace lazily as well as during new organization provisioning.
        """
        organization_id = _safe_str(organization.get("organization_id"))
        if not organization_id:
            return {}
        existing = self.list_workspaces(organization_id=organization_id)
        if existing:
            return existing[0]
        return self.save_workspace(
            {
                "workspace_id": f"education-cloud-{organization_id}",
                "organization_id": organization_id,
                "owner_user_id": _safe_str(organization.get("owner_user_id")),
                "name": f"{_safe_str(organization.get('name')) or 'Education'} Cloud",
                "status": "active",
                "visibility": "organization",
                "default_project_privacy": "workspace",
            }
        )

    def list_memberships(
        self,
        *,
        user_id: str = "",
        organization_id: str = "",
    ) -> list[Dict[str, Any]]:
        if user_id:
            return [
                item
                for item in self._list_by_index("user_updated_idx", "user_id", user_id)
                if _safe_str(item.get("entity_type")) == "membership"
            ]
        if organization_id:
            return [
                item
                for item in self._list_by_index(
                    "organization_updated_idx",
                    "organization_id",
                    organization_id,
                )
                if _safe_str(item.get("entity_type")) == "membership"
            ]
        return self._list_by_entity_type("membership")

    def get_membership(self, organization_id: str, user_id: str) -> Dict[str, Any]:
        return self._get_item(
            self._entity_id("membership", f"{_safe_str(organization_id)}:{_safe_str(user_id)}")
        )

    def get_membership_by_invite_token(self, invite_token: str) -> Dict[str, Any]:
        safe_token = _safe_str(invite_token)
        if not safe_token:
            return {}
        for membership in self._list_by_entity_type("membership"):
            if _safe_str(membership.get("invite_token")) == safe_token:
                return membership
        return {}

    def accept_invite(
        self,
        invite_token: str,
        user_id: str,
        *,
        accepted_email: str = "",
        updated_by_user_id: str = "",
    ) -> Dict[str, Any]:
        invite = self.get_membership_by_invite_token(invite_token)
        if not invite:
            raise FileNotFoundError("Education invite not found.")
        if _safe_str(invite.get("status")) != "pending":
            raise ValueError("Education invite is no longer pending.")
        organization_id = _safe_str(invite.get("organization_id"))
        safe_user_id = _safe_str(user_id)
        if not organization_id or not safe_user_id:
            raise ValueError("Education invite cannot be accepted.")
        invite_email = _safe_email(invite.get("email"))
        safe_accepted_email = _safe_email(accepted_email)
        if invite_email and not safe_accepted_email:
            raise PermissionError("Sign in with the invited email address to accept this education invite.")
        if invite_email and safe_accepted_email and invite_email != safe_accepted_email:
            raise PermissionError("This education invite was sent to a different email address.")
        existing = self.get_membership(organization_id, safe_user_id)
        if existing and _safe_str(existing.get("entity_id")) != _safe_str(invite.get("entity_id")):
            if _safe_str(existing.get("status")) == "active":
                old_entity_id = _safe_str(invite.get("entity_id"))
                if old_entity_id:
                    self._table.delete_item(Key={"entity_id": old_entity_id})
                return existing
            raise ValueError("This account already has an education seat record.")

        accepted = self.save_membership(
            {
                "organization_id": organization_id,
                "user_id": safe_user_id,
                "email": invite.get("email"),
                "role": invite.get("role") or "student",
                "status": "active",
                "seat_consumed": True,
                "invite_token": invite.get("invite_token"),
                "replaces_membership_entity_id": invite.get("entity_id"),
            },
            updated_by_user_id=updated_by_user_id or safe_user_id,
        )
        old_entity_id = _safe_str(invite.get("entity_id"))
        new_entity_id = _safe_str(accepted.get("entity_id"))
        if old_entity_id and old_entity_id != new_entity_id:
            self._table.delete_item(Key={"entity_id": old_entity_id})
        return accepted

    def list_education_student_usage(self, organization_id: str) -> list[Dict[str, Any]]:
        safe_organization_id = _safe_str(organization_id)
        if not safe_organization_id:
            return []
        memberships = [
            membership
            for membership in self.list_memberships(organization_id=safe_organization_id)
            if _safe_str(membership.get("role")).lower() == "student"
        ]
        projects = self.list_cloud_projects(organization_id=safe_organization_id)
        projects_by_user_id: dict[str, list[Dict[str, Any]]] = {}
        for project in projects:
            owner_user_id = _safe_str(project.get("user_id"))
            if not owner_user_id:
                continue
            projects_by_user_id.setdefault(owner_user_id, []).append(project)

        usage: list[Dict[str, Any]] = []
        for membership in memberships:
            status = _safe_str(membership.get("status")).lower()
            user_id = _safe_str(membership.get("user_id"))
            student_projects = projects_by_user_id.get(user_id, [])
            if status == "active" and user_id and not user_id.startswith("invite:"):
                student_projects = [
                    project
                    for project in self.list_owned_cloud_projects(user_id)
                    if not _safe_str(project.get("workspace_id"))
                ]
            project_count = len(
                [
                    project
                    for project in student_projects
                    if _safe_str(project.get("status") or "active").lower() == "active"
                ]
            )
            project_updated_values = [
                _safe_str(project.get("updated_at"))
                for project in student_projects
                if _safe_str(project.get("updated_at"))
            ]
            last_project_updated_at = max(project_updated_values) if project_updated_values else ""
            membership_updated_at = _safe_str(membership.get("updated_at"))
            last_active_at = max(
                value for value in [last_project_updated_at, membership_updated_at] if value
            ) if (last_project_updated_at or membership_updated_at) else ""
            usage.append(
                {
                    "organization_id": safe_organization_id,
                    "user_id": user_id,
                    "email": _safe_email(membership.get("email")),
                    "status": status,
                    "seat_consumed": _seat_reserved(membership),
                    "project_count": project_count,
                    "last_project_updated_at": last_project_updated_at,
                    "last_active_at": last_active_at,
                    "invited_at": _safe_str(membership.get("invited_at")),
                    "activated_at": _safe_str(membership.get("activated_at")),
                    "released_at": _safe_str(membership.get("released_at")),
                }
            )
        return sorted(
            usage,
            key=lambda item: (
                _safe_str(item.get("status")) == "active",
                _safe_str(item.get("last_active_at")),
            ),
            reverse=True,
        )

    def save_membership(
        self,
        payload: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        organization_id = _safe_str(payload.get("organization_id"))
        email = _safe_email(payload.get("email") or payload.get("student_email"))
        user_id = _safe_str(payload.get("user_id"))
        if not user_id and email:
            user_id = _invite_user_id(email)
        if not organization_id or not user_id:
            raise ValueError("Membership requires organization_id and user_id or email.")
        if not self.get_organization(organization_id):
            raise ValueError("Organization not found.")
        status = _safe_str(payload.get("status") or "active").lower() or "active"
        if status not in _MEMBERSHIP_STATUSES:
            raise ValueError("Membership status is invalid.")
        organization = self.get_organization(organization_id)
        role_default = "student" if _safe_str(organization.get("plan_code")) == "education" else "member"
        role = _safe_str(payload.get("role") or role_default).lower() or role_default
        if role not in _MEMBERSHIP_ROLES:
            raise ValueError("Membership role is invalid.")
        entity_id = self._entity_id("membership", f"{organization_id}:{user_id}")
        current = self._get_item(entity_id)
        replacing_entity_id = _safe_str(payload.get("replaces_membership_entity_id"))
        seat_consumed = _safe_bool(
            payload.get("seat_consumed"),
            default=_safe_bool(
                current.get("seat_consumed"),
                default=status in _RESERVED_SEAT_STATUSES,
            ),
        )
        if status in _RESERVED_SEAT_STATUSES and seat_consumed:
            if email:
                self._ensure_no_reserved_email_membership(
                    organization_id,
                    email,
                    excluding_membership_entity_ids={entity_id, replacing_entity_id},
                )
            self._ensure_available_seat(
                organization_id,
                excluding_membership_entity_id=replacing_entity_id or entity_id,
            )
        now = _utc_now_iso()
        existing_invite_token = _safe_str(current.get("invite_token") or payload.get("invite_token"))
        invite_token = existing_invite_token
        if status == "pending" and email and not invite_token:
            invite_token = uuid4().hex
        record = {
            "entity_id": entity_id,
            "entity_type": "membership",
            "organization_id": organization_id,
            "user_id": user_id,
            "email": email or _safe_email(current.get("email")),
            "role": role,
            "status": status,
            "seat_consumed": seat_consumed,
            "invite_token": invite_token,
            "invite_url": f"https://www.mixroom.ai/?auth=signup&invite={invite_token}" if invite_token else "",
            "app_invite_url": f"mixroom://education/invites/{invite_token}" if invite_token else "",
            "invited_at": _safe_str(current.get("invited_at")) or (now if status == "pending" else ""),
            "activated_at": _safe_str(current.get("activated_at")) or (now if status == "active" else ""),
            "released_at": now if status in {"revoked", "removed", "inactive"} else _safe_str(current.get("released_at")),
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_str(updated_by_email).lower(),
        }
        self._table.put_item(Item=record)
        return record

    def list_workspaces(
        self,
        *,
        organization_id: str = "",
        user_id: str = "",
    ) -> list[Dict[str, Any]]:
        if organization_id:
            return [
                item
                for item in self._list_by_index(
                    "organization_updated_idx",
                    "organization_id",
                    organization_id,
                )
                if _safe_str(item.get("entity_type")) == "workspace"
            ]
        if user_id:
            snapshot = self.build_user_access_snapshot(user_id)
            return snapshot.get("workspaces") or []
        return self._list_by_entity_type("workspace")

    def get_workspace(self, workspace_id: str) -> Dict[str, Any]:
        return self._get_item(self._entity_id("workspace", workspace_id))

    def save_workspace(
        self,
        payload: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        workspace_id = _safe_str(payload.get("workspace_id")) or uuid4().hex
        organization_id = _safe_str(payload.get("organization_id"))
        if not organization_id:
            raise ValueError("Workspace organization_id is required.")
        if not self.get_organization(organization_id):
            raise ValueError("Organization not found.")
        current = self.get_workspace(workspace_id) or {}
        status = _payload_or_current_str(payload, current, "status", default="active").lower() or "active"
        if status not in _WORKSPACE_STATUSES:
            raise ValueError("Workspace status is invalid.")
        now = _utc_now_iso()
        record = {
            "entity_id": self._entity_id("workspace", workspace_id),
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": organization_id,
            "user_id": _safe_str(payload.get("owner_user_id") or current.get("user_id")),
            "name": _payload_or_current_str(payload, current, "name", default=workspace_id),
            "status": status,
            "visibility": _safe_str(payload.get("visibility") or current.get("visibility") or "organization"),
            "default_project_privacy": _safe_str(
                payload.get("default_project_privacy")
                or current.get("default_project_privacy")
                or "workspace"
            ),
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_str(updated_by_email).lower(),
            "locked_at": _payload_or_current_str(payload, current, "locked_at"),
            "archived_at": _payload_or_current_str(payload, current, "archived_at"),
        }
        self._table.put_item(Item=record)
        return record

    def list_cloud_projects(
        self,
        *,
        workspace_id: str = "",
        organization_id: str = "",
        user_id: str = "",
    ) -> list[Dict[str, Any]]:
        if workspace_id:
            return [
                item
                for item in self._list_by_index(
                    "workspace_updated_idx",
                    "workspace_id",
                    workspace_id,
                )
                if _safe_str(item.get("entity_type")) == "cloud_project"
            ]
        if organization_id:
            workspaces = self.list_workspaces(organization_id=organization_id)
            results: list[Dict[str, Any]] = []
            for workspace in workspaces:
                results.extend(
                    self.list_cloud_projects(
                        workspace_id=_safe_str(workspace.get("workspace_id"))
                    )
                )
            return results
        if user_id:
            snapshot = self.build_user_access_snapshot(user_id)
            return snapshot.get("cloud_projects") or []
        return self._list_by_entity_type("cloud_project")

    def list_owned_cloud_projects(self, user_id: str) -> list[Dict[str, Any]]:
        safe_user_id = _safe_str(user_id)
        if not safe_user_id:
            return []
        return [
            item
            for item in self._list_by_index("user_updated_idx", "user_id", safe_user_id)
            if _safe_str(item.get("entity_type")) == "cloud_project"
            and _safe_str(item.get("status") or "active") != "archived"
            and _is_cloud_project_bundle(item)
            and (
                _safe_str(item.get("document_key"))
                or _safe_str(item.get("pending_upload_key"))
            )
        ]

    def cloud_project_storage_usage(
        self,
        user_id: str,
        *,
        excluding_project_id: str = "",
    ) -> Dict[str, int]:
        safe_excluding = _safe_str(excluding_project_id)
        projects = [
            project
            for project in self.list_owned_cloud_projects(user_id)
            if _safe_str(project.get("project_id")) != safe_excluding
        ]
        return {
            "project_count": len(projects),
            "used_bytes": sum(
                max(
                    0,
                    max(
                        _safe_int(project.get("document_size_bytes"), default=0),
                        _safe_int(
                            project.get("pending_upload_size_bytes"),
                            default=0,
                        ),
                    ),
                )
                for project in projects
            ),
        }

    def create_personal_cloud_project_upload(
        self,
        user_id: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        return self.create_cloud_project_upload(user_id, payload)

    def create_cloud_project_upload(
        self,
        user_id: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        object_client = self._object_client()
        if not config.CLOUD_PROJECT_DOCUMENTS_BUCKET or object_client is None:
            raise ValueError("Cloud project documents bucket is not configured.")
        safe_user_id = _safe_str(user_id)
        if not safe_user_id:
            raise ValueError("Cloud project owner is required.")
        requested_workspace_id = _safe_str(payload.get("workspace_id"))
        workspace: Dict[str, Any] = {}
        organization: Dict[str, Any] = {}
        organization_id = ""
        if requested_workspace_id:
            workspace = self.get_workspace(requested_workspace_id)
            if not workspace or not _workspace_allows_read(workspace):
                raise FileNotFoundError("Workspace not found.")
            if not _workspace_allows_write(workspace):
                raise PermissionError("Cloud workspace is read-only for this account.")
            workspace_organization_id = _safe_str(workspace.get("organization_id"))
            requested_organization_id = _safe_str(payload.get("organization_id"))
            if (
                requested_organization_id
                and requested_organization_id != workspace_organization_id
            ):
                raise FileNotFoundError("Workspace not found.")
            organization_id = workspace_organization_id
            organization = self.get_organization(organization_id)
            if not organization or not _org_allows_read(organization):
                raise FileNotFoundError("Workspace not found.")
            if not _org_allows_write(organization):
                raise PermissionError("Cloud workspace is read-only for this account.")
            if not self._workspace_visible_to_user(
                workspace,
                organization=organization,
                user_id=safe_user_id,
            ):
                raise FileNotFoundError("Workspace not found.")
            membership = self._active_membership_for_org(
                safe_user_id,
                organization_id,
            )
            is_workspace_owner = _safe_str(workspace.get("user_id")) == safe_user_id
            role = _safe_str(membership.get("role")) if membership else ""
            if not is_workspace_owner and role not in _WORKSPACE_CREATE_ROLES:
                raise PermissionError("Cloud workspace is read-only for this account.")
        requested_project_id = _safe_object_component(payload.get("project_id"))
        local_project_id = _safe_str(payload.get("local_project_id"))
        if requested_project_id:
            project_id = requested_project_id
        else:
            local_for_id = local_project_id or uuid4().hex
            project_scope = requested_workspace_id or safe_user_id
            digest = hashlib.sha1(f"{project_scope}:{local_for_id}".encode("utf-8")).hexdigest()
            project_id = (
                f"workspace-{digest[:24]}"
                if requested_workspace_id
                else f"personal-{digest[:24]}"
            )
        size_bytes = _safe_int(payload.get("size_bytes"), default=-1)
        if size_bytes <= 0:
            raise ValueError("Cloud project size_bytes must be greater than zero.")
        name = _safe_str(payload.get("name")) or "Untitled Project"
        local_project_id = local_project_id or project_id
        current = self.get_cloud_project(project_id) or {}
        if current:
            current_workspace_id = _safe_str(current.get("workspace_id"))
            if requested_workspace_id:
                if current_workspace_id != requested_workspace_id:
                    raise PermissionError("Cloud project belongs to another account.")
                current_context = self._cloud_project_access_context(
                    safe_user_id,
                    project_id,
                )
                if not current_context["can_write"]:
                    raise PermissionError(
                        "Cloud project is read-only for this account."
                    )
            elif _safe_str(current.get("user_id")) != safe_user_id or current_workspace_id:
                raise PermissionError("Cloud project belongs to another account.")
        expected_revision = _optional_int(payload.get("expected_revision"))
        current_revision = _safe_int(current.get("document_revision"), default=0)
        if expected_revision is not None and expected_revision != current_revision:
            raise ValueError("Cloud project revision conflict.")
        old_pending_key = _safe_str(current.get("pending_upload_key"))
        old_bucket = _safe_str(current.get("document_bucket"))
        if old_bucket and old_pending_key:
            try:
                object_client.delete_object(Bucket=old_bucket, Key=old_pending_key)
            except (BotoCoreError, ClientError):
                pass

        now = _utc_now_iso()
        if requested_workspace_id:
            workspace_component = _safe_object_component(
                requested_workspace_id,
                fallback="workspace",
            )
            final_key = (
                f"workspaces/{workspace_component}/"
                f"projects/{project_id}/latest.mixroom"
            )
            pending_key = (
                f"pending-uploads/workspaces/{workspace_component}/"
                f"projects/{project_id}/{uuid4().hex}.mixroom"
            )
        else:
            final_key = (
                f"users/{_safe_object_component(safe_user_id, fallback='user')}/"
                f"projects/{project_id}/latest.mixroom"
            )
            pending_key = (
                f"pending-uploads/users/{_safe_object_component(safe_user_id, fallback='user')}/"
                f"projects/{project_id}/{uuid4().hex}.mixroom"
            )
        visibility = (
            _safe_str(payload.get("visibility"))
            or _safe_str(workspace.get("default_project_privacy"))
            or "private"
        )
        record = {
            **current,
            "entity_id": self._entity_id("cloud_project", project_id),
            "entity_type": "cloud_project",
            "project_id": project_id,
            "user_id": _safe_str(current.get("user_id")) or safe_user_id,
            "name": name,
            "status": "active",
            "visibility": visibility,
            "storage_mode": cloud_project_storage_mode(),
            "storage_provider": cloud_project_storage_provider(),
            "document_revision": current_revision,
            "document_bucket": config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            "document_key": _safe_str(current.get("document_key")),
            "document_size_bytes": _safe_int(current.get("document_size_bytes"), default=0),
            "local_project_id": local_project_id,
            "pending_upload": True,
            "pending_upload_key": pending_key,
            "pending_upload_size_bytes": size_bytes,
            "pending_upload_name": name,
            "pending_upload_started_at": now,
            "target_document_key": final_key,
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": safe_user_id,
            "updated_by_email": "",
        }
        if requested_workspace_id:
            record["workspace_id"] = requested_workspace_id
            record["organization_id"] = organization_id
        self._table.put_item(Item=record)
        upload_url = object_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
                "Key": pending_key,
                "ContentType": _MIXROOM_CONTENT_TYPE,
                **put_object_extra_args(),
            },
            ExpiresIn=900,
        )
        return {
            **record,
            "upload_url": upload_url,
            "upload_headers": upload_headers(_MIXROOM_CONTENT_TYPE),
            "can_write": True,
        }

    def complete_personal_cloud_project_upload(
        self,
        user_id: str,
        project_id: str,
    ) -> Dict[str, Any]:
        context = self._cloud_project_access_context(user_id, project_id)
        if not context["can_write"]:
            raise PermissionError("Cloud project is read-only for this account.")
        project = context["project"]
        bucket = _safe_str(project.get("document_bucket"))
        pending_key = _safe_str(project.get("pending_upload_key"))
        final_key = _safe_str(project.get("target_document_key")) or _safe_str(
            project.get("document_key")
        )
        if not final_key:
            final_key = (
                f"users/{_safe_object_component(user_id, fallback='user')}/"
                f"projects/{_safe_object_component(project_id, fallback=uuid4().hex)}/"
                "latest.mixroom"
            )
        object_client = self._object_client()
        if not bucket or not pending_key or object_client is None:
            raise FileNotFoundError("Cloud project upload not found.")
        try:
            head = object_client.head_object(Bucket=bucket, Key=pending_key)
        except (BotoCoreError, ClientError) as exc:
            raise FileNotFoundError("Cloud project upload not found.") from exc
        actual_size = _safe_int(head.get("ContentLength"), default=0)
        if actual_size <= 0:
            raise ValueError("Cloud project upload is empty.")
        expected_size = _safe_int(project.get("pending_upload_size_bytes"), default=0)
        if expected_size > 0 and actual_size != expected_size:
            try:
                object_client.delete_object(Bucket=bucket, Key=pending_key)
            except (BotoCoreError, ClientError):
                pass
            raise ValueError("Cloud project upload size did not match the reserved size.")
        copy_result = object_client.copy_object(
            Bucket=bucket,
            Key=final_key,
            CopySource={"Bucket": bucket, "Key": pending_key},
            ContentType=_MIXROOM_CONTENT_TYPE,
            MetadataDirective="REPLACE",
            **copy_object_extra_args(),
        )
        try:
            object_client.delete_object(Bucket=bucket, Key=pending_key)
        except (BotoCoreError, ClientError):
            pass
        now = _utc_now_iso()
        record = {
            **project,
            "name": _safe_str(project.get("pending_upload_name"))
            or _safe_str(project.get("name"))
            or project_id,
            "document_key": final_key,
            "document_size_bytes": actual_size,
            "document_revision": _safe_int(project.get("document_revision"), default=0) + 1,
            "document_version_id": _safe_str(copy_result.get("VersionId")),
            "pending_upload": False,
            "pending_upload_key": "",
            "pending_upload_size_bytes": 0,
            "pending_upload_name": "",
            "pending_upload_started_at": "",
            "target_document_key": "",
            "updated_at": now,
            "updated_by_user_id": _safe_str(user_id),
        }
        self._table.put_item(Item=record)
        return {**record, "can_write": True}

    def abort_personal_cloud_project_upload(
        self,
        user_id: str,
        project_id: str,
    ) -> None:
        context = self._cloud_project_access_context(user_id, project_id)
        if not context["can_write"]:
            raise PermissionError("Cloud project is read-only for this account.")
        project = context["project"]
        bucket = _safe_str(project.get("document_bucket"))
        pending_key = _safe_str(project.get("pending_upload_key"))
        object_client = self._object_client()
        if bucket and pending_key and object_client is not None:
            try:
                object_client.delete_object(Bucket=bucket, Key=pending_key)
            except (BotoCoreError, ClientError):
                pass
        if not _safe_str(project.get("document_key")):
            self._table.delete_item(Key={"entity_id": _safe_str(project.get("entity_id"))})
            return
        record = {
            **project,
            "pending_upload": False,
            "pending_upload_key": "",
            "pending_upload_size_bytes": 0,
            "pending_upload_name": "",
            "pending_upload_started_at": "",
            "target_document_key": "",
        }
        self._table.put_item(Item=record)

    def get_cloud_project_download_url(
        self,
        user_id: str,
        project_id: str,
    ) -> Dict[str, Any]:
        context = self._cloud_project_access_context(user_id, project_id)
        project = context["project"]
        if not _is_cloud_project_bundle(project):
            raise FileNotFoundError("Cloud project bundle not found.")
        bucket = _safe_str(project.get("document_bucket"))
        key = _safe_str(project.get("document_key"))
        object_client = self._object_client()
        if not bucket or not key or object_client is None:
            raise FileNotFoundError("Cloud project bundle not found.")
        download_url = object_client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": bucket,
                "Key": key,
                "ResponseContentType": _MIXROOM_CONTENT_TYPE,
                "ResponseContentDisposition": (
                    "attachment; filename=\""
                    f"{_safe_object_component(project.get('name'), fallback='mixroom-project')}.mixroom"
                    "\""
                ),
            },
            ExpiresIn=900,
        )
        return {
            **project,
            "download_url": download_url,
            "can_write": context["can_write"],
        }

    def delete_personal_cloud_project(
        self,
        user_id: str,
        project_id: str,
    ) -> None:
        context = self._cloud_project_access_context(user_id, project_id)
        if _safe_str(context["project"].get("workspace_id")) and not context["can_write"]:
            raise PermissionError("Cloud project is read-only for this account.")
        project = context["project"]
        if _safe_str(project.get("user_id")) != _safe_str(user_id):
            raise PermissionError("Only the owner can delete this cloud project.")
        if not _is_cloud_project_bundle(project):
            raise FileNotFoundError("Cloud project bundle not found.")
        bucket = _safe_str(project.get("document_bucket"))
        keys = {
            _safe_str(project.get("document_key")),
            _safe_str(project.get("pending_upload_key")),
        }
        if bucket and self._object_client() is not None:
            for key in keys:
                if not key:
                    continue
                self._delete_s3_key_versions(bucket, key)
        self._table.delete_item(Key={"entity_id": _safe_str(project.get("entity_id"))})

    def _delete_s3_key_versions(self, bucket: str, key: str) -> None:
        object_client = self._object_client()
        if object_client is None or not bucket or not key:
            return
        if not supports_object_versions():
            try:
                object_client.delete_object(Bucket=bucket, Key=key)
            except (BotoCoreError, ClientError):
                pass
            return
        try:
            paginator = object_client.get_paginator("list_object_versions")
            pages = paginator.paginate(Bucket=bucket, Prefix=key)
            objects: list[Dict[str, str]] = []
            for page in pages:
                for item in (page.get("Versions") or []) + (page.get("DeleteMarkers") or []):
                    if _safe_str(item.get("Key")) != key:
                        continue
                    version_id = _safe_str(item.get("VersionId"))
                    if version_id:
                        objects.append({"Key": key, "VersionId": version_id})
                while len(objects) >= 1000:
                    batch = objects[:1000]
                    objects = objects[1000:]
                    object_client.delete_objects(
                        Bucket=bucket,
                        Delete={"Objects": batch, "Quiet": True},
                    )
            if objects:
                object_client.delete_objects(
                    Bucket=bucket,
                    Delete={"Objects": objects, "Quiet": True},
                )
                return
        except (AttributeError, BotoCoreError, ClientError):
            pass
        try:
            object_client.delete_object(Bucket=bucket, Key=key)
        except (BotoCoreError, ClientError):
            pass

    def save_cloud_project(
        self,
        payload: Dict[str, Any],
        *,
        updated_by_user_id: str = "",
        updated_by_email: str = "",
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        workspace_id = _safe_str(payload.get("workspace_id"))
        if not workspace_id:
            raise ValueError("Cloud project workspace_id is required.")
        workspace = self.get_workspace(workspace_id)
        if not workspace:
            raise ValueError("Workspace not found.")
        project_id = _safe_str(payload.get("project_id")) or uuid4().hex
        status = _safe_str(payload.get("status") or "active").lower() or "active"
        if status not in _PROJECT_STATUSES:
            raise ValueError("Cloud project status is invalid.")
        entity_id = self._entity_id("cloud_project", project_id)
        current = self._get_item(entity_id)
        now = _utc_now_iso()
        document = _coerce_json_document(payload.get("document"))
        document_metadata = self._store_project_document(project_id, document) if document is not None else {}
        current_revision = _safe_int(current.get("document_revision"), default=0)
        document_revision = (
            current_revision + 1
            if document is not None
            else _safe_int(
                payload.get("document_revision"),
                default=current_revision,
            )
        )
        storage_mode = _safe_str(
            payload.get("storage_mode") or current.get("storage_mode") or "metadata_only"
        )
        if document is not None and document_metadata:
            storage_mode = "s3_json"
        record = {
            "entity_id": entity_id,
            "entity_type": "cloud_project",
            "project_id": project_id,
            "workspace_id": workspace_id,
            "organization_id": _safe_str(
                payload.get("organization_id") or workspace.get("organization_id")
            ),
            "user_id": _safe_str(payload.get("owner_user_id") or current.get("user_id")),
            "name": _safe_str(payload.get("name")) or project_id,
            "status": status,
            "storage_mode": storage_mode,
            "document_revision": document_revision,
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_str(updated_by_email).lower(),
            **document_metadata,
        }
        self._table.put_item(Item=record)
        return record

    def get_cloud_project(self, project_id: str) -> Dict[str, Any]:
        return self._get_item(self._entity_id("cloud_project", project_id))

    def get_user_cloud_project(self, user_id: str, project_id: str) -> Dict[str, Any]:
        context = self._cloud_project_access_context(user_id, project_id)
        return {
            **context["project"],
            "document": self._load_project_document(context["project"]),
            "can_write": context["can_write"],
        }

    def update_user_cloud_project(
        self,
        user_id: str,
        project_id: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        if self._table is None:
            raise RuntimeError("Collaboration table is not configured.")
        context = self._cloud_project_access_context(user_id, project_id)
        if not context["can_write"]:
            raise PermissionError("Cloud project is read-only for this account.")
        document = _coerce_json_document(payload.get("document"))
        if document is None:
            raise ValueError("Cloud project document must be a JSON object.")
        expected_revision = _optional_int(payload.get("expected_revision"))
        if expected_revision is None:
            raise ValueError("expected_revision is required.")

        current = context["project"]
        current_revision = _safe_int(current.get("document_revision"), default=0)
        if expected_revision != current_revision:
            raise ValueError("Cloud project revision conflict.")

        now = _utc_now_iso()
        document_metadata = self._store_project_document(project_id, document)
        record = {
            **current,
            "name": _safe_str(payload.get("name")) or _safe_str(current.get("name")) or project_id,
            "storage_mode": "s3_json" if document_metadata else _safe_str(current.get("storage_mode")),
            "document_revision": current_revision + 1,
            "updated_at": now,
            "updated_by_user_id": _safe_str(user_id),
            "updated_by_email": "",
            **document_metadata,
        }
        self._table.put_item(Item=record)
        return {
            **record,
            "document": document,
            "can_write": True,
        }

    def build_user_access_snapshot(self, user_id: str) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        if not safe_user_id or self._table is None:
            return {
                "generated_at": _utc_now_iso(),
                "configurable": self._table is not None,
                "memberships": [],
                "organizations": [],
                "workspaces": [],
                "cloud_projects": [],
                "summary": {
                    "organization_count": 0,
                    "workspace_count": 0,
                    "cloud_project_count": 0,
                },
                "storage": {
                    "project_count": 0,
                    "used_bytes": 0,
                },
            }

        memberships = [
            item
            for item in self.list_memberships(user_id=safe_user_id)
            if _safe_str(item.get("entity_type")) == "membership"
        ]
        active_memberships = [
            item for item in memberships if _safe_str(item.get("status")) == "active"
        ]
        organizations: list[Dict[str, Any]] = []
        seen_org_ids: set[str] = set()
        for membership in active_memberships:
            organization_id = _safe_str(membership.get("organization_id"))
            if not organization_id or organization_id in seen_org_ids:
                continue
            organization = self.get_organization(organization_id)
            if not organization:
                continue
            seen_org_ids.add(organization_id)
            organizations.append(
                {
                    **organization,
                    "membership_role": _safe_str(membership.get("role")),
                    "membership_status": _safe_str(membership.get("status")),
                    "can_write": _org_allows_write(organization),
                    "access_status": "active" if _org_allows_write(organization) else "read_only",
                }
            )

        workspaces: list[Dict[str, Any]] = []
        seen_workspace_ids: set[str] = set()
        for organization in organizations:
            if not _org_allows_read(organization):
                continue
            if _safe_str(organization.get("plan_code")).lower() == "education":
                # Older Education organizations intentionally had no shared
                # workspace. Upgrade their persisted access flag before
                # exposing the class cloud, otherwise the visibility check
                # below would still hide it from students.
                if not _safe_bool(
                    organization.get("shared_workspace_enabled"),
                    default=True,
                ):
                    organization.update(
                        self.save_organization(
                            {
                                "organization_id": _safe_str(
                                    organization.get("organization_id")
                                ),
                                "shared_workspace_enabled": True,
                            }
                        )
                    )
                self.ensure_education_cloud_workspace(organization)
            for workspace in self.list_workspaces(
                organization_id=_safe_str(organization.get("organization_id"))
            ):
                workspace_id = _safe_str(workspace.get("workspace_id"))
                if not workspace_id or workspace_id in seen_workspace_ids:
                    continue
                if not _workspace_allows_read(workspace):
                    continue
                if not self._workspace_visible_to_user(
                    workspace,
                    organization=organization,
                    user_id=safe_user_id,
                ):
                    continue
                seen_workspace_ids.add(workspace_id)
                workspaces.append(
                    {
                        **workspace,
                        "can_write": _org_allows_write(organization)
                        and _workspace_allows_write(workspace),
                        "access_status": "active"
                        if _org_allows_write(organization)
                        and _workspace_allows_write(workspace)
                        else "read_only",
                    }
                )

        cloud_projects: list[Dict[str, Any]] = []
        seen_project_ids: set[str] = set()
        for project in self.list_owned_cloud_projects(safe_user_id):
            if _safe_str(project.get("workspace_id")):
                continue
            project_id = _safe_str(project.get("project_id"))
            if not project_id or project_id in seen_project_ids:
                continue
            seen_project_ids.add(project_id)
            cloud_projects.append({**project, "can_write": True})
        for workspace in workspaces:
            if not _workspace_allows_read(workspace):
                continue
            for project in self.list_cloud_projects(
                workspace_id=_safe_str(workspace.get("workspace_id"))
            ):
                project_id = _safe_str(project.get("project_id"))
                if not project_id or project_id in seen_project_ids:
                    continue
                if not self._project_visible_to_user(
                    project,
                    workspace=workspace,
                    user_id=safe_user_id,
                ):
                    continue
                seen_project_ids.add(project_id)
                cloud_projects.append({**project, "can_write": self._safe_can_write_project(safe_user_id, project, workspace)})

        return {
            "generated_at": _utc_now_iso(),
            "configurable": True,
            "memberships": memberships,
            "organizations": organizations,
            "workspaces": workspaces,
            "cloud_projects": cloud_projects,
            "summary": {
                "organization_count": len(organizations),
                "workspace_count": len(workspaces),
                "cloud_project_count": len(cloud_projects),
            },
            "storage": self.cloud_project_storage_usage(safe_user_id),
        }

    def _store_project_document(
        self,
        project_id: str,
        document: Dict[str, Any],
    ) -> Dict[str, Any]:
        object_client = self._object_client()
        if not config.CLOUD_PROJECT_DOCUMENTS_BUCKET or object_client is None:
            raise ValueError("Cloud project documents bucket is not configured.")
        body = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )
        key = f"cloud-projects/{project_id}/latest.json"
        response = object_client.put_object(
            Bucket=config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            Key=key,
            Body=body,
            ContentType="application/json",
            **put_object_extra_args(),
        )
        return {
            "document_bucket": config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            "document_key": key,
            "document_size_bytes": len(body),
            "document_version_id": _safe_str(response.get("VersionId")),
        }

    def _entity_id(self, entity_type: str, identifier: str) -> str:
        return f"{entity_type}#{_safe_str(identifier)}"

    def _ensure_available_seat(
        self,
        organization_id: str,
        *,
        excluding_membership_entity_id: str = "",
    ) -> None:
        organization = self.get_organization(organization_id)
        seat_limit = _safe_int(organization.get("seat_limit"), default=0)
        if seat_limit <= 0:
            return
        seats_used = self._organization_seat_summary(
            organization_id,
            excluding_membership_entity_id=excluding_membership_entity_id,
        )["used"]
        if seats_used >= seat_limit:
            raise ValueError("Organization seat limit reached.")

    def _ensure_no_reserved_email_membership(
        self,
        organization_id: str,
        email: str,
        *,
        excluding_membership_entity_ids: set[str],
    ) -> None:
        safe_email = _safe_email(email)
        if not safe_email:
            return
        excluded = {_safe_str(entity_id) for entity_id in excluding_membership_entity_ids}
        for membership in self.list_memberships(organization_id=organization_id):
            if _safe_str(membership.get("entity_id")) in excluded:
                continue
            if _safe_email(membership.get("email")) != safe_email:
                continue
            if _seat_reserved(membership):
                raise ValueError("Student email already has a reserved education seat.")

    def _organization_seat_summary(
        self,
        organization_id: str,
        *,
        excluding_membership_entity_id: str = "",
    ) -> Dict[str, int]:
        active = 0
        invited = 0
        for membership in self.list_memberships(organization_id=organization_id):
            if _safe_str(membership.get("entity_id")) == excluding_membership_entity_id:
                continue
            if not _seat_reserved(membership):
                continue
            if _safe_str(membership.get("status")) == "pending":
                invited += 1
            else:
                active += 1
        used = active + invited
        return {
            "active": active,
            "invited": invited,
            "used": used,
        }

    def _with_organization_seat_summary(self, organization: Dict[str, Any]) -> Dict[str, Any]:
        if not organization:
            return {}
        record = dict(organization)
        seat_limit = _safe_int(record.get("seat_limit"), default=0)
        summary = self._organization_seat_summary(_safe_str(record.get("organization_id")))
        record["seats_active"] = summary["active"]
        record["seats_invited"] = summary["invited"]
        record["seats_used"] = summary["used"]
        record["seats_available"] = max(seat_limit - summary["used"], 0) if seat_limit > 0 else 0
        if _safe_str(record.get("plan_code")) == "education":
            record.setdefault("seat_options", list(_EDUCATION_SEAT_OPTIONS))
            record.setdefault("education_admin_enabled", True)
            record.setdefault("teacher_mode_enabled", True)
        return record

    def _cloud_project_access_context(
        self,
        user_id: str,
        project_id: str,
    ) -> Dict[str, Any]:
        safe_user_id = _safe_str(user_id)
        safe_project_id = _safe_str(project_id)
        if not safe_user_id or not safe_project_id:
            raise FileNotFoundError("Cloud project not found.")
        project = self.get_cloud_project(safe_project_id)
        if not project:
            raise FileNotFoundError("Cloud project not found.")
        if _safe_str(project.get("user_id")) == safe_user_id and not _safe_str(
            project.get("workspace_id")
        ):
            return {
                "project": project,
                "workspace": {},
                "organization": {},
                "membership": {},
                "can_write": True,
            }
        workspace = self.get_workspace(_safe_str(project.get("workspace_id")))
        if not workspace:
            raise FileNotFoundError("Cloud project not found.")
        organization_id = _safe_str(
            project.get("organization_id") or workspace.get("organization_id")
        )
        organization = self.get_organization(organization_id)
        if not organization or not _org_allows_read(organization):
            raise FileNotFoundError("Cloud project not found.")

        membership = self._active_membership_for_org(safe_user_id, organization_id)
        is_owner = (
            _safe_str(project.get("user_id")) == safe_user_id
            or _safe_str(workspace.get("user_id")) == safe_user_id
        )
        if membership is None and not is_owner:
            raise FileNotFoundError("Cloud project not found.")
        if not self._workspace_visible_to_user(
            workspace,
            organization=organization,
            user_id=safe_user_id,
        ):
            raise FileNotFoundError("Cloud project not found.")
        if not _workspace_allows_read(workspace):
            raise FileNotFoundError("Cloud project not found.")
        if not self._project_visible_to_user(
            project,
            workspace=workspace,
            user_id=safe_user_id,
        ):
            raise FileNotFoundError("Cloud project not found.")

        role = _safe_str(membership.get("role")) if membership else ""
        can_write = (
            _org_allows_write(organization)
            and _workspace_allows_write(workspace)
            and (is_owner or role in _WRITE_ACCESS_ROLES)
        )
        return {
            "project": project,
            "workspace": workspace,
            "organization": organization,
            "membership": membership or {},
            "can_write": can_write,
        }

    def _safe_can_write_project(
        self,
        user_id: str,
        project: Dict[str, Any],
        workspace: Dict[str, Any],
    ) -> bool:
        organization = self.get_organization(
            _safe_str(project.get("organization_id") or workspace.get("organization_id"))
        )
        if not organization or not _org_allows_write(organization):
            return False
        if not _workspace_allows_write(workspace):
            return False
        if _safe_str(project.get("user_id")) == user_id:
            return True
        membership = self._active_membership_for_org(
            user_id,
            _safe_str(project.get("organization_id") or workspace.get("organization_id")),
        )
        return bool(membership and _safe_str(membership.get("role")) in _WRITE_ACCESS_ROLES)

    def _active_membership_for_org(
        self,
        user_id: str,
        organization_id: str,
    ) -> Dict[str, Any] | None:
        for membership in self.list_memberships(user_id=user_id):
            if _safe_str(membership.get("organization_id")) != organization_id:
                continue
            if _safe_str(membership.get("status")) != "active":
                continue
            return membership
        return None

    def _workspace_visible_to_user(
        self,
        workspace: Dict[str, Any],
        *,
        organization: Dict[str, Any],
        user_id: str,
    ) -> bool:
        owner_user_id = _safe_str(workspace.get("user_id"))
        if owner_user_id and owner_user_id == user_id:
            return True
        if not _safe_bool(
            organization.get("shared_workspace_enabled"),
            default=True,
        ):
            return False
        visibility = _safe_str(workspace.get("visibility")).lower()
        return visibility not in _PRIVATE_ACCESS_VALUES

    def _project_visible_to_user(
        self,
        project: Dict[str, Any],
        *,
        workspace: Dict[str, Any],
        user_id: str,
    ) -> bool:
        owner_user_id = _safe_str(project.get("user_id"))
        if owner_user_id and owner_user_id == user_id:
            return True
        visibility = _safe_str(project.get("visibility")).lower()
        if visibility:
            return visibility not in _PRIVATE_ACCESS_VALUES
        default_project_privacy = _safe_str(
            workspace.get("default_project_privacy")
        ).lower()
        if owner_user_id and default_project_privacy in _PRIVATE_ACCESS_VALUES:
            return False
        return True

    def _load_project_document(self, project: Dict[str, Any]) -> Dict[str, Any] | None:
        bucket = _safe_str(project.get("document_bucket"))
        key = _safe_str(project.get("document_key"))
        object_client = self._object_client()
        if not bucket or not key or object_client is None:
            return None
        try:
            response = object_client.get_object(Bucket=bucket, Key=key)
            body = response.get("Body")
            if body is None:
                return None
            raw = body.read()
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8")
            parsed = json.loads(raw or "{}")
            return parsed if isinstance(parsed, dict) else None
        except (BotoCoreError, ClientError, json.JSONDecodeError, UnicodeDecodeError):
            return None

    def _get_item(self, entity_id: str) -> Dict[str, Any]:
        if self._table is None:
            return {}
        try:
            return self._table.get_item(Key={"entity_id": entity_id}).get("Item") or {}
        except (BotoCoreError, ClientError):
            return {}

    def _list_by_entity_type(self, entity_type: str) -> list[Dict[str, Any]]:
        return [
            item
            for item in self._list_by_index("type_updated_idx", "entity_type", entity_type)
            if _safe_str(item.get("entity_type")) == entity_type
        ]

    def _list_by_index(
        self,
        index_name: str,
        key_name: str,
        key_value: str,
    ) -> list[Dict[str, Any]]:
        if self._table is None:
            return []
        items: list[Dict[str, Any]] = []
        if Key is not None:
            try:
                start_key = None
                while True:
                    kwargs: Dict[str, Any] = {
                        "IndexName": index_name,
                        "KeyConditionExpression": Key(key_name).eq(key_value),
                        "ScanIndexForward": False,
                    }
                    if start_key:
                        kwargs["ExclusiveStartKey"] = start_key
                    response = self._table.query(**kwargs)
                    items.extend(
                        item
                        for item in response.get("Items", [])
                        if isinstance(item, dict)
                    )
                    start_key = response.get("LastEvaluatedKey")
                    if not start_key:
                        break
                return items
            except ClientError as exc:
                code = str(exc.response.get("Error", {}).get("Code") or "").strip()
                if code != "ValidationException":
                    raise

        start_key = None
        while True:
            kwargs = {}
            if start_key:
                kwargs["ExclusiveStartKey"] = start_key
            if Attr is not None:
                kwargs["FilterExpression"] = Attr(key_name).eq(key_value)
            response = self._table.scan(**kwargs)
            items.extend(
                item
                for item in response.get("Items", [])
                if isinstance(item, dict)
                and (Attr is not None or _safe_str(item.get(key_name)) == key_value)
            )
            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break
        return items
