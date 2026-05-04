from __future__ import annotations

import json
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

_ORG_STATUSES = frozenset({"draft", "active", "suspended", "archived"})
_MEMBERSHIP_STATUSES = frozenset({"pending", "active", "inactive", "revoked"})
_MEMBERSHIP_ROLES = frozenset({"owner", "admin", "manager", "member", "viewer"})
_WORKSPACE_STATUSES = frozenset({"active", "archived"})
_PROJECT_STATUSES = frozenset({"draft", "active", "archived"})
_PRIVATE_ACCESS_VALUES = frozenset({"private", "owner", "personal", "invite_only"})
_WRITE_ACCESS_ROLES = frozenset({"owner", "admin", "manager"})


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


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


def _coerce_json_document(value: Any) -> Dict[str, Any] | None:
    if value is None:
        return None
    if isinstance(value, dict):
        return value
    raise ValueError("Cloud project document must be a JSON object.")


class CollaborationRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._s3 = boto3.client("s3") if boto3 is not None else None
        self._table = None
        if self._ddb is not None and config.COLLABORATION_TABLE:
            self._table = self._ddb.Table(config.COLLABORATION_TABLE)

    def is_configured(self) -> bool:
        return self._table is not None

    def list_organizations(self) -> list[Dict[str, Any]]:
        return self._list_by_entity_type("organization")

    def get_organization(self, organization_id: str) -> Dict[str, Any]:
        entity_id = self._entity_id("organization", organization_id)
        return self._get_item(entity_id)

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
        status = _safe_str(payload.get("status") or "active").lower() or "active"
        if status not in _ORG_STATUSES:
            raise ValueError("Organization status is invalid.")
        current = self.get_organization(organization_id) or {}
        now = _utc_now_iso()
        record = {
            "entity_id": self._entity_id("organization", organization_id),
            "entity_type": "organization",
            "organization_id": organization_id,
            "name": _safe_str(payload.get("name")) or organization_id,
            "status": status,
            "plan_code": _safe_str(payload.get("plan_code") or current.get("plan_code") or "studio").lower(),
            "seat_limit": _safe_int(payload.get("seat_limit"), default=_safe_int(current.get("seat_limit"), default=0)),
            "shared_workspace_enabled": _safe_bool(
                payload.get("shared_workspace_enabled"),
                default=_safe_bool(current.get("shared_workspace_enabled"), default=True),
            ),
            "support_notes": _safe_str(payload.get("support_notes") or current.get("support_notes")),
            "created_at": _safe_str(current.get("created_at")) or now,
            "updated_at": now,
            "updated_by_user_id": _safe_str(updated_by_user_id),
            "updated_by_email": _safe_str(updated_by_email).lower(),
        }
        self._table.put_item(Item=record)
        return record

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
        user_id = _safe_str(payload.get("user_id"))
        if not organization_id or not user_id:
            raise ValueError("Membership requires organization_id and user_id.")
        if not self.get_organization(organization_id):
            raise ValueError("Organization not found.")
        status = _safe_str(payload.get("status") or "active").lower() or "active"
        if status not in _MEMBERSHIP_STATUSES:
            raise ValueError("Membership status is invalid.")
        role = _safe_str(payload.get("role") or "member").lower() or "member"
        if role not in _MEMBERSHIP_ROLES:
            raise ValueError("Membership role is invalid.")
        entity_id = self._entity_id("membership", f"{organization_id}:{user_id}")
        current = self._get_item(entity_id)
        seat_consumed = _safe_bool(
            payload.get("seat_consumed"),
            default=_safe_bool(current.get("seat_consumed"), default=status == "active"),
        )
        if status == "active" and seat_consumed:
            self._ensure_available_seat(
                organization_id,
                excluding_membership_entity_id=entity_id,
            )
        now = _utc_now_iso()
        record = {
            "entity_id": entity_id,
            "entity_type": "membership",
            "organization_id": organization_id,
            "user_id": user_id,
            "role": role,
            "status": status,
            "seat_consumed": seat_consumed,
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
        status = _safe_str(payload.get("status") or "active").lower() or "active"
        if status not in _WORKSPACE_STATUSES:
            raise ValueError("Workspace status is invalid.")
        current = self.get_workspace(workspace_id) or {}
        now = _utc_now_iso()
        record = {
            "entity_id": self._entity_id("workspace", workspace_id),
            "entity_type": "workspace",
            "workspace_id": workspace_id,
            "organization_id": organization_id,
            "user_id": _safe_str(payload.get("owner_user_id") or current.get("user_id")),
            "name": _safe_str(payload.get("name")) or workspace_id,
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
                }
            )

        workspaces: list[Dict[str, Any]] = []
        seen_workspace_ids: set[str] = set()
        for organization in organizations:
            if _safe_str(organization.get("status")) != "active":
                continue
            for workspace in self.list_workspaces(
                organization_id=_safe_str(organization.get("organization_id"))
            ):
                workspace_id = _safe_str(workspace.get("workspace_id"))
                if not workspace_id or workspace_id in seen_workspace_ids:
                    continue
                if not self._workspace_visible_to_user(
                    workspace,
                    organization=organization,
                    user_id=safe_user_id,
                ):
                    continue
                seen_workspace_ids.add(workspace_id)
                workspaces.append(workspace)

        cloud_projects: list[Dict[str, Any]] = []
        seen_project_ids: set[str] = set()
        for workspace in workspaces:
            if _safe_str(workspace.get("status")) != "active":
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
                cloud_projects.append(project)

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
        }

    def _store_project_document(
        self,
        project_id: str,
        document: Dict[str, Any],
    ) -> Dict[str, Any]:
        if not config.CLOUD_PROJECT_DOCUMENTS_BUCKET or self._s3 is None:
            raise ValueError("Cloud project documents bucket is not configured.")
        body = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )
        key = f"cloud-projects/{project_id}/latest.json"
        response = self._s3.put_object(
            Bucket=config.CLOUD_PROJECT_DOCUMENTS_BUCKET,
            Key=key,
            Body=body,
            ContentType="application/json",
            ServerSideEncryption="AES256",
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
        seats_used = 0
        for membership in self.list_memberships(organization_id=organization_id):
            if _safe_str(membership.get("entity_id")) == excluding_membership_entity_id:
                continue
            if _safe_str(membership.get("status")) != "active":
                continue
            if not _safe_bool(membership.get("seat_consumed"), default=False):
                continue
            seats_used += 1
        if seats_used >= seat_limit:
            raise ValueError("Organization seat limit reached.")

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
        workspace = self.get_workspace(_safe_str(project.get("workspace_id")))
        if not workspace:
            raise FileNotFoundError("Cloud project not found.")
        organization_id = _safe_str(
            project.get("organization_id") or workspace.get("organization_id")
        )
        organization = self.get_organization(organization_id)
        if not organization or _safe_str(organization.get("status")) != "active":
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
        if not self._project_visible_to_user(
            project,
            workspace=workspace,
            user_id=safe_user_id,
        ):
            raise FileNotFoundError("Cloud project not found.")

        role = _safe_str(membership.get("role")) if membership else ""
        return {
            "project": project,
            "workspace": workspace,
            "organization": organization,
            "membership": membership or {},
            "can_write": is_owner or role in _WRITE_ACCESS_ROLES,
        }

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
        if not bucket or not key or self._s3 is None:
            return None
        try:
            response = self._s3.get_object(Bucket=bucket, Key=key)
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
