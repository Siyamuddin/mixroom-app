from __future__ import annotations

import time
from html import escape
from typing import Any, Dict
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.billing_catalog import merge_capabilities, merge_limits
from common.billing_catalog_repository import BillingCatalogRepository
from common.collaboration_repository import CollaborationRepository
from common.email_delivery import EmailDeliveryError, EmailSuppressedError, send_auth_email
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.models import (
    entitlement_capabilities_for_status,
    entitlement_limits_for_status,
    free_entitlement,
    normalize_plan_code,
    status_has_active_access,
    subscription_effective_status,
)
from common.repository import BillingRepository

repo = CollaborationRepository()
billing_repo = BillingRepository()
catalog_repo = BillingCatalogRepository()
init_sentry("mixroom-app-api-collaboration")


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    rc = event.get("requestContext") or {}
    http = rc.get("http") or {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _path_param(event: Dict[str, Any], name: str) -> str:
    params = event.get("pathParameters") or {}
    if isinstance(params, dict):
        return str(params.get(name) or "").strip()
    return ""


def _user_profile_summary(
    user_id: str,
    cache: Dict[str, Dict[str, Any]],
) -> Dict[str, Any]:
    safe_user_id = str(user_id or "").strip()
    if not safe_user_id:
        return {}
    if safe_user_id in cache:
        return cache[safe_user_id]
    try:
        profile = billing_repo.get_user_profile(safe_user_id) or {}
    except Exception:
        profile = {}
    summary = {
        "user_id": safe_user_id,
        "username": str(profile.get("username") or "").strip(),
        "display_name": str(profile.get("display_name") or "").strip(),
    }
    cache[safe_user_id] = summary
    return summary


def _user_profile_email(user_id: str) -> str:
    safe_user_id = str(user_id or "").strip()
    if not safe_user_id:
        return ""
    try:
        profile = billing_repo.get_user_profile(safe_user_id) or {}
    except Exception:
        return ""
    return str(profile.get("email_lc") or profile.get("email") or "").strip().lower()


def _enrich_cloud_projects_with_profiles(
    cloud_projects: list[Dict[str, Any]],
) -> list[Dict[str, Any]]:
    cache: Dict[str, Dict[str, Any]] = {}
    enriched: list[Dict[str, Any]] = []
    for project in cloud_projects:
        owner_user_id = str(project.get("user_id") or "").strip()
        updated_by_user_id = str(project.get("updated_by_user_id") or "").strip()
        enriched.append(
            {
                **project,
                "owner_profile": _user_profile_summary(owner_user_id, cache),
                "updated_by_profile": _user_profile_summary(
                    updated_by_user_id or owner_user_id,
                    cache,
                ),
            }
        )
    return enriched


def _is_teacher_membership(membership: Dict[str, Any]) -> bool:
    if str(membership.get("status") or "").strip().lower() != "active":
        return False
    role = str(membership.get("role") or "").strip().lower()
    return role in {"owner", "admin", "manager", "teacher"}


def _teacher_organization_ids(snapshot: Dict[str, Any]) -> set[str]:
    return {
        str(membership.get("organization_id") or "").strip()
        for membership in snapshot.get("memberships") or []
        if _is_teacher_membership(membership)
    }


def _education_teacher_organization_ids(snapshot: Dict[str, Any]) -> set[str]:
    teacher_org_ids = _teacher_organization_ids(snapshot)
    return {
        str(organization.get("organization_id") or "").strip()
        for organization in snapshot.get("organizations") or []
        if str(organization.get("organization_id") or "").strip() in teacher_org_ids
        and str(organization.get("plan_code") or "").strip().lower() == "education"
    }


def _admin_organizations(snapshot: Dict[str, Any]) -> list[Dict[str, Any]]:
    admin_org_ids = _teacher_organization_ids(snapshot)
    organizations = []
    cache: Dict[str, Dict[str, Any]] = {}
    for organization in snapshot.get("organizations") or []:
        organization_id = str(organization.get("organization_id") or "").strip()
        if organization_id not in admin_org_ids:
            continue
        plan_code = str(organization.get("plan_code") or "").strip().lower()
        if plan_code not in {"studio", "enterprise", "education"}:
            continue
        owner_user_id = str(organization.get("owner_user_id") or "").strip()
        organizations.append(
            {
                **organization,
                "owner_profile": _user_profile_summary(owner_user_id, cache),
            }
        )
    return organizations


def _organization_admin_ids(snapshot: Dict[str, Any]) -> set[str]:
    return {
        str(organization.get("organization_id") or "").strip()
        for organization in _admin_organizations(snapshot)
    }


def _enrich_memberships_with_profiles(
    memberships: list[Dict[str, Any]],
) -> list[Dict[str, Any]]:
    cache: Dict[str, Dict[str, Any]] = {}
    enriched = []
    for membership in memberships:
        user_id = str(membership.get("user_id") or "").strip()
        profile = {} if user_id.startswith("invite:") else _user_profile_summary(user_id, cache)
        enriched.append(
            {
                **membership,
                "user_profile": profile,
                "username": membership.get("username") or profile.get("username"),
                "display_name": membership.get("display_name") or profile.get("display_name"),
            }
        )
    return enriched


def _enrich_organizations_with_admin_profiles(
    organizations: list[Dict[str, Any]],
) -> list[Dict[str, Any]]:
    cache: Dict[str, Dict[str, Any]] = {}
    enriched: list[Dict[str, Any]] = []
    for organization in organizations:
        organization_id = str(organization.get("organization_id") or "").strip()
        owner_user_id = str(organization.get("owner_user_id") or "").strip()
        admin_profiles: list[Dict[str, Any]] = []
        if organization_id:
            try:
                memberships = repo.list_memberships(organization_id=organization_id)
            except Exception:
                memberships = []
            if not isinstance(memberships, list):
                memberships = []
            for membership in memberships:
                if not _is_teacher_membership(membership):
                    continue
                user_id = str(membership.get("user_id") or "").strip()
                if not user_id or user_id.startswith("invite:"):
                    continue
                profile = _user_profile_summary(user_id, cache)
                if profile:
                    admin_profiles.append(
                        {
                            **profile,
                            "role": str(membership.get("role") or "").strip(),
                        }
                    )
        enriched.append(
            {
                **organization,
                "owner_profile": _user_profile_summary(owner_user_id, cache),
                "admin_profiles": admin_profiles,
            }
        )
    return enriched


def _catalog_plan(plan_code: str) -> Dict[str, Any]:
    catalog = catalog_repo.get_catalog()
    for plan in catalog.get("plans") or []:
        if str(plan.get("code") or "").strip().lower() == plan_code:
            return plan
    return {}


def _org_status_allows_read(status: Any) -> bool:
    return str(status or "active").strip().lower() in {"active", "past_due", "locked", "suspended"}


def _org_status_allows_write(status: Any) -> bool:
    return str(status or "active").strip().lower() in {"active", "past_due"}


def _workspace_status_allows_read(status: Any) -> bool:
    return str(status or "active").strip().lower() in {"active", "locked"}


def _workspace_status_allows_write(status: Any) -> bool:
    return str(status or "active").strip().lower() == "active"


def _organization_supports_shared_cloud(organization: Dict[str, Any]) -> bool:
    plan_code = str(organization.get("plan_code") or "").strip().lower()
    if plan_code == "education":
        # Education has a dedicated class cloud. It remains a separate
        # location from each student's personal cloud storage.
        return True
    plan = _catalog_plan(plan_code)
    limits = plan.get("limits") if isinstance(plan.get("limits"), dict) else {}
    return bool(
        (plan.get("capabilities") or {}).get("team_workspaces")
        or str(plan.get("group") or "").strip().lower() in {"team", "enterprise"}
        or limits.get("shared_storage_gb") not in (None, "")
    )


def _plan_rank(plan: Dict[str, Any]) -> int:
    try:
        return int(plan.get("rank") or 0)
    except (TypeError, ValueError):
        return 0


def _explicit_limit_overrides(raw: Dict[str, Any]) -> Dict[str, Any]:
    overrides = raw.get("limit_overrides")
    if isinstance(overrides, dict):
        return overrides
    if raw.get("limits_are_overrides") is True and isinstance(raw.get("limits"), dict):
        return raw["limits"]
    return {}


def _personal_entitlement_for_cloud(
    user_id: str,
    *,
    snapshot: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    raw = billing_repo.get_entitlement(user_id)
    if not raw:
        raw = free_entitlement(user_id=user_id).to_dict()
        billing_repo.put_entitlement(raw)
    status = subscription_effective_status(raw)
    active = status_has_active_access(status)
    plan_code = normalize_plan_code(raw.get("plan_code") or raw.get("tier") or "free")
    if not active:
        plan_code = "free"
    plan = _catalog_plan(plan_code)
    if str(plan.get("group") or "").strip().lower() in {"team", "enterprise", "education"}:
        plan_code = "free"
        plan = _catalog_plan("free")
    capabilities = entitlement_capabilities_for_status(plan_code, status)
    limits = entitlement_limits_for_status(plan_code, status)
    if active:
        capabilities = merge_capabilities(
            plan.get("capabilities") or {},
            capabilities,
            raw.get("capabilities") if isinstance(raw.get("capabilities"), dict) else {},
        )
        limits = merge_limits(
            plan.get("limits") or {},
            limits,
            _explicit_limit_overrides(raw),
        )
    return {
        "plan_code": plan.get("code") or plan_code,
        "capabilities": capabilities,
        "limits": limits,
    }


def _effective_entitlement_for_cloud(
    user_id: str,
    *,
    workspace_id: str = "",
) -> Dict[str, Any]:
    personal = _personal_entitlement_for_cloud(user_id)
    if not str(workspace_id or "").strip():
        return personal

    safe_workspace_id = str(workspace_id or "").strip()
    try:
        snapshot = repo.build_user_access_snapshot(user_id)
    except Exception:
        snapshot = {}
    workspace = next(
        (
            item
            for item in snapshot.get("workspaces") or []
            if str(item.get("workspace_id") or "").strip() == safe_workspace_id
        ),
        {},
    )
    if not workspace:
        raise PermissionError("Cloud workspace is not available for this account.")
    organization_id = str(workspace.get("organization_id") or "").strip()
    for organization in snapshot.get("organizations") or []:
        if str(organization.get("organization_id") or "").strip() != organization_id:
            continue
        if not _org_status_allows_read(organization.get("status")):
            continue
        if str(organization.get("membership_status") or "active").strip().lower() != "active":
            continue
        if not _organization_supports_shared_cloud(organization):
            break
        org_plan = _catalog_plan(str(organization.get("plan_code") or "").strip().lower())
        limits = _shared_cloud_limits_for_org(org_plan, organization)
        capabilities = merge_capabilities(org_plan.get("capabilities") or {})
        if not _org_status_allows_write(organization.get("status")):
            capabilities["cloud_projects"] = False
        return {
            "plan_code": org_plan.get("code") or organization.get("plan_code") or "free",
            "capabilities": capabilities,
            "limits": limits,
        }
    raise PermissionError("Cloud workspace is not available for this account.")


def _shared_cloud_limits_for_org(
    plan: Dict[str, Any],
    organization: Dict[str, Any],
) -> Dict[str, Any]:
    plan_limits = plan.get("limits") if isinstance(plan.get("limits"), dict) else {}
    limits = dict(plan_limits)
    shared_storage = limits.get("shared_storage_gb")
    if shared_storage not in (None, ""):
        limits["storage_gb"] = shared_storage
        return limits

    if "storage_gb" in limits:
        return limits
    limits["storage_gb"] = 0
    return limits


def _project_storage_size(project: Dict[str, Any]) -> int:
    try:
        document_size = int(project.get("document_size_bytes") or 0)
    except (TypeError, ValueError):
        document_size = 0
    try:
        pending_size = int(project.get("pending_upload_size_bytes") or 0)
    except (TypeError, ValueError):
        pending_size = 0
    return max(0, document_size, pending_size)


def _storage_usage_for_projects(
    projects: list[Dict[str, Any]],
    *,
    excluding_project_id: str = "",
) -> Dict[str, int]:
    safe_excluding = str(excluding_project_id or "").strip()
    selected = [
        project
        for project in projects
        if str(project.get("project_id") or "").strip() != safe_excluding
    ]
    return {
        "project_count": len(selected),
        "used_bytes": sum(_project_storage_size(project) for project in selected),
    }


def _snapshot_for_user(user_id: str) -> Dict[str, Any]:
    try:
        return repo.build_user_access_snapshot(user_id)
    except Exception:
        return {
            "organizations": [],
            "workspaces": [],
            "cloud_projects": [],
        }


def _personal_cloud_projects(
    snapshot: Dict[str, Any],
    user_id: str,
) -> list[Dict[str, Any]]:
    safe_user_id = str(user_id or "").strip()
    return [
        project
        for project in snapshot.get("cloud_projects") or []
        if not str(project.get("workspace_id") or "").strip()
        and str(project.get("user_id") or "").strip() == safe_user_id
    ]


def _workspace_cloud_projects(
    snapshot: Dict[str, Any],
    workspace_id: str,
) -> list[Dict[str, Any]]:
    safe_workspace_id = str(workspace_id or "").strip()
    return [
        project
        for project in snapshot.get("cloud_projects") or []
        if str(project.get("workspace_id") or "").strip() == safe_workspace_id
    ]


def _int_limit(value: Any) -> int | None:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    normalized = str(value or "").strip().lower()
    if not normalized or normalized == "custom":
        return None
    try:
        return int(float(normalized))
    except ValueError:
        return None


def _storage_limit_bytes(limits: Dict[str, Any]) -> int | None:
    raw = limits.get("storage_gb")
    if str(raw or "").strip().lower() == "custom":
        return None
    try:
        gb = float(raw)
    except (TypeError, ValueError):
        return 0
    return int(max(0.0, gb) * 1024 * 1024 * 1024)


def _cloud_storage_payload(
    user_id: str,
    entitlement: Dict[str, Any] | None = None,
    *,
    snapshot: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    snapshot = snapshot or _snapshot_for_user(user_id)
    personal_entitlement = entitlement or _personal_entitlement_for_cloud(
        user_id,
        snapshot=snapshot,
    )
    personal_limits = (
        personal_entitlement.get("limits")
        if isinstance(personal_entitlement.get("limits"), dict)
        else {}
    )
    personal_usage = _storage_usage_for_projects(
        _personal_cloud_projects(snapshot, user_id),
    )
    locations: list[Dict[str, Any]] = [
        {
            "storage_scope": "personal",
            "workspace_id": "",
            "organization_id": "",
            "label": "Personal Cloud",
            "used_bytes": personal_usage.get("used_bytes") or 0,
            "project_count": personal_usage.get("project_count") or 0,
            "limit_bytes": _storage_limit_bytes(personal_limits),
            "project_limit": _int_limit(personal_limits.get("cloud_projects")),
            "plan_code": personal_entitlement.get("plan_code") or "free",
            "status": "active",
            "workspace_status": "",
            "organization_status": "",
            "can_write": True,
        }
    ]
    organizations_by_id = {
        str(organization.get("organization_id") or "").strip(): organization
        for organization in snapshot.get("organizations") or []
    }
    for workspace in snapshot.get("workspaces") or []:
        workspace_id = str(workspace.get("workspace_id") or "").strip()
        if not workspace_id:
            continue
        organization_id = str(workspace.get("organization_id") or "").strip()
        organization = organizations_by_id.get(organization_id, {})
        if not _workspace_status_allows_read(workspace.get("status")):
            continue
        if not _org_status_allows_read(organization.get("status")):
            continue
        if str(organization.get("membership_status") or "active").strip().lower() != "active":
            continue
        if not _organization_supports_shared_cloud(organization):
            continue
        org_plan = _catalog_plan(str(organization.get("plan_code") or "").strip().lower())
        shared_limits = _shared_cloud_limits_for_org(org_plan, organization)
        can_write = _workspace_status_allows_write(workspace.get("status")) and _org_status_allows_write(
            organization.get("status")
        )
        usage = _storage_usage_for_projects(
            _workspace_cloud_projects(snapshot, workspace_id),
        )
        label = (
            str(organization.get("name") or "").strip()
            or str(workspace.get("name") or "").strip()
            or "Shared Cloud"
        )
        if str(organization.get("plan_code") or "").strip().lower() == "education":
            label = f"{label} Cloud" if not label.lower().endswith("cloud") else label
        locations.append(
            {
                "storage_scope": "workspace",
                "workspace_id": workspace_id,
                "organization_id": organization_id,
                "label": label,
                "used_bytes": usage.get("used_bytes") or 0,
                "project_count": usage.get("project_count") or 0,
                "limit_bytes": _storage_limit_bytes(shared_limits),
                "project_limit": _int_limit(shared_limits.get("cloud_projects")),
                "plan_code": org_plan.get("code") or organization.get("plan_code") or "free",
                "status": str(organization.get("status") or workspace.get("status") or "active").strip().lower(),
                "workspace_status": str(workspace.get("status") or "active").strip().lower(),
                "organization_status": str(organization.get("status") or "active").strip().lower(),
                "can_write": can_write,
            }
    )
    return {
        "used_bytes": personal_usage.get("used_bytes") or 0,
        "project_count": personal_usage.get("project_count") or 0,
        "limit_bytes": _storage_limit_bytes(personal_limits),
        "project_limit": _int_limit(personal_limits.get("cloud_projects")),
        "plan_code": personal_entitlement.get("plan_code") or "free",
        "locations": locations,
    }


def _enforce_cloud_project_quota(
    *,
    user_id: str,
    project_id: str,
    size_bytes: int,
    workspace_id: str = "",
) -> Dict[str, Any]:
    entitlement = _effective_entitlement_for_cloud(user_id, workspace_id=workspace_id)
    capabilities = entitlement.get("capabilities") if isinstance(entitlement.get("capabilities"), dict) else {}
    limits = entitlement.get("limits") if isinstance(entitlement.get("limits"), dict) else {}
    if not bool(capabilities.get("cloud_projects")):
        raise PermissionError("Your current plan does not include cloud projects.")
    snapshot = _snapshot_for_user(user_id)
    if str(workspace_id or "").strip():
        projects = _workspace_cloud_projects(snapshot, workspace_id)
    else:
        projects = _personal_cloud_projects(snapshot, user_id)
    usage_without_project = _storage_usage_for_projects(
        projects,
        excluding_project_id=project_id,
    )
    project_limit = _int_limit(limits.get("cloud_projects"))
    if project_limit is not None and usage_without_project.get("project_count", 0) >= project_limit:
        raise PermissionError("Cloud project limit reached for your current plan.")
    storage_limit = _storage_limit_bytes(limits)
    if storage_limit is not None and usage_without_project.get("used_bytes", 0) + size_bytes > storage_limit:
        raise PermissionError("Cloud storage limit reached for your current plan.")
    return entitlement


def _send_education_invite_email(
    *,
    membership: Dict[str, Any],
    organization: Dict[str, Any],
    locale: str = "",
) -> tuple[bool, str]:
    email = str(membership.get("email") or "").strip().lower()
    email_locale = _education_invite_email_locale(locale)
    invite_url = _url_with_query_param(
        str(membership.get("invite_url") or "").strip(),
        "lang",
        email_locale,
    )
    app_invite_url = str(membership.get("app_invite_url") or "").strip()
    if not email or not invite_url:
        return False, "missing_invite_email_or_url"
    organization_name = str(organization.get("name") or "Mixroom Education").strip()
    safe_org = escape(organization_name)
    safe_url = escape(invite_url, quote=True)
    safe_app_url = escape(app_invite_url, quote=True)
    if email_locale == "ko":
        subject = f"{organization_name}에서 Mixroom 교육 좌석에 초대했습니다"
        app_line = f"\nMixroom 앱에서 바로 열기:\n{app_invite_url}\n" if app_invite_url else ""
        text_body = (
            f"{organization_name}에서 Mixroom 교육 좌석에 초대했습니다.\n\n"
            f"아래 링크에서 초대를 수락하세요:\n{invite_url}\n\n"
            f"{app_line}"
            "예상하지 못한 초대라면 이 이메일을 무시해 주세요."
        )
        app_link_html = (
            f"<p><a href=\"{safe_app_url}\">Mixroom 앱에서 열기</a></p>"
            if app_invite_url
            else ""
        )
        html_body = (
            f"<p><strong>{safe_org}</strong>에서 Mixroom 교육 좌석에 초대했습니다.</p>"
            f"<p><a href=\"{safe_url}\">교육 초대 수락하기</a></p>"
            f"{app_link_html}"
            "<p>예상하지 못한 초대라면 이 이메일을 무시해 주세요.</p>"
        )
    else:
        subject = f"You're invited to {organization_name} on Mixroom"
        app_line = (
            f"\nOpen directly in the Mixroom app:\n{app_invite_url}\n"
            if app_invite_url
            else ""
        )
        text_body = (
            f"You have been invited to join {organization_name} on Mixroom.\n\n"
            f"Accept your education seat here:\n{invite_url}\n\n"
            f"{app_line}"
            "If you were not expecting this invite, you can ignore this email."
        )
        app_link_html = (
            f"<p><a href=\"{safe_app_url}\">Open in the Mixroom app</a></p>"
            if app_invite_url
            else ""
        )
        html_body = (
            f"<p>You have been invited to join <strong>{safe_org}</strong> on Mixroom.</p>"
            f"<p><a href=\"{safe_url}\">Accept your education seat</a></p>"
            f"{app_link_html}"
            "<p>If you were not expecting this invite, you can ignore this email.</p>"
        )
    try:
        send_auth_email(
            to_email=email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )
        return True, ""
    except EmailSuppressedError:
        return False, "suppressed"
    except EmailDeliveryError:
        return False, "delivery_failed"


def _send_organization_invite_email(
    *,
    membership: Dict[str, Any],
    organization: Dict[str, Any],
    locale: str = "",
) -> tuple[bool, str]:
    if str(organization.get("plan_code") or "").strip().lower() == "education":
        return _send_education_invite_email(
            membership=membership,
            organization=organization,
            locale=locale,
        )
    email = str(membership.get("email") or "").strip().lower()
    email_locale = _education_invite_email_locale(locale)
    invite_url = _url_with_query_param(
        str(membership.get("invite_url") or "").strip(),
        "lang",
        email_locale,
    )
    if not email or not invite_url:
        return False, "missing_invite_email_or_url"
    organization_name = str(organization.get("name") or "Mixroom Studio").strip()
    safe_org = escape(organization_name)
    safe_url = escape(invite_url, quote=True)
    if email_locale == "ko":
        subject = f"{organization_name}에서 Mixroom 팀에 초대했습니다"
        text_body = (
            f"{organization_name}에서 Mixroom 팀 좌석에 초대했습니다.\n\n"
            f"아래 링크에서 초대를 수락하세요:\n{invite_url}\n\n"
            "예상하지 못한 초대라면 이 이메일을 무시해 주세요."
        )
        html_body = (
            f"<p><strong>{safe_org}</strong>에서 Mixroom 팀 좌석에 초대했습니다.</p>"
            f"<p><a href=\"{safe_url}\">팀 초대 수락하기</a></p>"
            "<p>예상하지 못한 초대라면 이 이메일을 무시해 주세요.</p>"
        )
    else:
        subject = f"You're invited to {organization_name} on Mixroom"
        text_body = (
            f"You have been invited to join {organization_name} on Mixroom.\n\n"
            f"Accept your team seat here:\n{invite_url}\n\n"
            "If you were not expecting this invite, you can ignore this email."
        )
        html_body = (
            f"<p>You have been invited to join <strong>{safe_org}</strong> on Mixroom.</p>"
            f"<p><a href=\"{safe_url}\">Accept your team seat</a></p>"
            "<p>If you were not expecting this invite, you can ignore this email.</p>"
        )
    try:
        send_auth_email(
            to_email=email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )
        return True, ""
    except EmailSuppressedError:
        return False, "suppressed"
    except EmailDeliveryError:
        return False, "delivery_failed"


def _education_invite_email_locale(locale: str) -> str:
    safe = str(locale or "").strip().lower()
    return "ko" if safe.startswith("ko") else "en"


def _teacher_locale(user_id: str) -> str:
    try:
        profile = billing_repo.get_user_profile(str(user_id or "").strip()) or {}
    except Exception:
        profile = {}
    return str(profile.get("locale_code") or "").strip()


def _url_with_query_param(url: str, key: str, value: str) -> str:
    safe_url = str(url or "").strip()
    safe_key = str(key or "").strip()
    safe_value = str(value or "").strip()
    if not safe_url or not safe_key or not safe_value:
        return safe_url
    parts = urlsplit(safe_url)
    query = [
        (existing_key, existing_value)
        for existing_key, existing_value in parse_qsl(parts.query, keep_blank_values=True)
        if existing_key != safe_key
    ]
    query.append((safe_key, safe_value))
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment)
    )


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    user_id = extract_user_id_from_event(event)
    request_context = build_request_log_context(event, _context, user_id=user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not user_id:
        return _finalize(unauthorized(), error="unauthorized")

    try:
        path = _path(event)
        method = _method(event)
        if method not in {"DELETE", "GET", "POST", "PUT"}:
            return _finalize(json_response(404, {"error": "Not found"}), error="not_found")

        if path.endswith("/v1/cloud-projects/me") and method == "POST":
            body = parse_json_body(event)
            requested_project_id = str(
                body.get("project_id") or body.get("local_project_id") or ""
            ).strip()
            requested_workspace_id = str(body.get("workspace_id") or "").strip()
            if requested_project_id and not requested_workspace_id:
                # Older downloads could retain the cloud project ID without
                # its workspace scope. Resolve an accessible existing project
                # before quota enforcement so an update uses its workspace
                # allowance instead of being misclassified as a new personal
                # cloud project.
                try:
                    existing_project = repo.get_user_cloud_project(
                        user_id,
                        requested_project_id,
                    )
                except (FileNotFoundError, PermissionError):
                    existing_project = {}
                requested_workspace_id = str(
                    existing_project.get("workspace_id") or ""
                ).strip()
                if requested_workspace_id:
                    body["workspace_id"] = requested_workspace_id
                    existing_organization_id = str(
                        existing_project.get("organization_id") or ""
                    ).strip()
                    if existing_organization_id:
                        body["organization_id"] = existing_organization_id
            size_bytes = int(body.get("size_bytes") or 0)
            entitlement = _enforce_cloud_project_quota(
                user_id=user_id,
                project_id=requested_project_id,
                size_bytes=size_bytes,
                workspace_id=requested_workspace_id,
            )
            return _finalize(
                json_response(
                    200,
                    {
                        "cloud_project": repo.create_cloud_project_upload(
                            user_id,
                            body,
                        ),
                        "storage": _cloud_storage_payload(user_id),
                    },
                )
            )

        if path.startswith("/v1/cloud-projects/") and not path.endswith("/v1/cloud-projects/me"):
            project_id = _path_param(event, "project_id") or path.rsplit("/", 1)[-1]
            if path.endswith("/download") and method == "GET":
                project_id = _path_param(event, "project_id") or path.split("/")[-2]
                return _finalize(
                    json_response(
                        200,
                        {
                            "cloud_project": repo.get_cloud_project_download_url(
                                user_id,
                                project_id,
                            ),
                        },
                    )
                )
            if method == "DELETE":
                repo.delete_personal_cloud_project(user_id, project_id)
                return _finalize(json_response(200, {"deleted": True}))
            if path.endswith("/complete") and method == "POST":
                project_id = _path_param(event, "project_id") or path.split("/")[-2]
                pending_project = repo.get_user_cloud_project(user_id, project_id)
                pending_size_bytes = int(
                    pending_project.get("pending_upload_size_bytes") or 0
                )
                try:
                    _enforce_cloud_project_quota(
                        user_id=user_id,
                        project_id=project_id,
                        size_bytes=pending_size_bytes,
                        workspace_id=str(pending_project.get("workspace_id") or "").strip(),
                    )
                except PermissionError:
                    repo.abort_personal_cloud_project_upload(user_id, project_id)
                    raise
                completed = repo.complete_personal_cloud_project_upload(
                    user_id,
                    project_id,
                )
                return _finalize(json_response(200, {"cloud_project": completed}))
            if method == "GET":
                return _finalize(
                    json_response(
                        200,
                        {
                            "cloud_project": _enrich_cloud_projects_with_profiles(
                                [repo.get_user_cloud_project(user_id, project_id)]
                            )[0],
                        },
                    )
                )
            if method == "PUT":
                body = parse_json_body(event)
                return _finalize(
                    json_response(
                        200,
                        {
                            "cloud_project": repo.update_user_cloud_project(
                                user_id,
                                project_id,
                                body,
                            ),
                        },
                    )
                )
            return _finalize(json_response(404, {"error": "Not found"}), error="not_found")

        snapshot = repo.build_user_access_snapshot(user_id)
        if path.endswith("/v1/organizations/me/admin") and method == "GET":
            organizations = _admin_organizations(snapshot)
            memberships: list[Dict[str, Any]] = []
            student_usage: list[Dict[str, Any]] = []
            for organization in organizations:
                organization_id = str(organization.get("organization_id") or "").strip()
                memberships.extend(repo.list_memberships(organization_id=organization_id))
                if str(organization.get("plan_code") or "").strip().lower() == "education":
                    student_usage.extend(repo.list_education_student_usage(organization_id))
            return _finalize(
                json_response(
                    200,
                    {
                        "organizations": organizations,
                        "memberships": _enrich_memberships_with_profiles(memberships),
                        "student_usage": student_usage,
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/organizations/me/invites") and method == "POST":
            body = parse_json_body(event)
            organization_id = str(body.get("organization_id") or "").strip()
            admin_org_ids = _organization_admin_ids(snapshot)
            if organization_id not in admin_org_ids:
                return _finalize(
                    json_response(403, {"error": "Organization admin access required."}),
                    error="forbidden",
                )
            organization = repo.get_organization(organization_id)
            plan_code = str(organization.get("plan_code") or "").strip().lower()
            role = "student" if plan_code == "education" else "member"
            membership = repo.save_membership(
                {
                    "organization_id": organization_id,
                    "email": body.get("email") or body.get("student_email"),
                    "role": role,
                    "status": "pending",
                    "seat_consumed": True,
                },
                updated_by_user_id=user_id,
            )
            email_sent, email_error = _send_organization_invite_email(
                membership=membership,
                organization=organization,
                locale=_teacher_locale(user_id),
            )
            response = {"membership": membership, "email_sent": email_sent}
            if email_error:
                response["email_error"] = email_error
            return _finalize(json_response(200, response))
        if path.endswith("/v1/organizations/me/memberships") and method == "POST":
            body = parse_json_body(event)
            organization_id = str(body.get("organization_id") or "").strip()
            admin_org_ids = _organization_admin_ids(snapshot)
            if organization_id not in admin_org_ids:
                return _finalize(
                    json_response(403, {"error": "Organization admin access required."}),
                    error="forbidden",
                )
            status = str(body.get("status") or "").strip().lower()
            if status not in {"pending", "active", "inactive", "revoked", "removed"}:
                return _finalize(
                    json_response(400, {"error": "Membership status is invalid."}),
                    error="bad_request",
                )
            target_user_id = str(body.get("user_id") or "").strip()
            if not target_user_id:
                return _finalize(
                    json_response(400, {"error": "Membership user is required."}),
                    error="bad_request",
                )
            existing = repo.get_membership(organization_id, target_user_id)
            if not existing:
                return _finalize(
                    json_response(404, {"error": "Membership not found."}),
                    error="not_found",
                )
            existing_role = str(existing.get("role") or "").strip().lower()
            if existing_role in {"owner", "admin", "manager", "teacher"}:
                return _finalize(
                    json_response(403, {"error": "Admin and owner memberships cannot be changed here."}),
                    error="forbidden",
                )
            organization = repo.get_organization(organization_id)
            plan_code = str(organization.get("plan_code") or "").strip().lower()
            role = "student" if plan_code == "education" else existing_role or "member"
            membership = repo.save_membership(
                {
                    "organization_id": organization_id,
                    "user_id": target_user_id,
                    "email": existing.get("email") or body.get("email"),
                    "role": role,
                    "status": status,
                    "seat_consumed": status in {"pending", "active"},
                },
                updated_by_user_id=user_id,
            )
            return _finalize(json_response(200, {"membership": membership}))
        if path.startswith("/v1/education/invites/"):
            invite_token = _path_param(event, "invite_token")
            if not invite_token:
                parts = [part for part in path.split("/") if part]
                try:
                    invite_token = parts[parts.index("invites") + 1]
                except (ValueError, IndexError):
                    invite_token = ""
            if not invite_token:
                return _finalize(
                    json_response(404, {"error": "Education invite not found."}),
                    error="not_found",
                )
            if method == "GET":
                invite = repo.get_membership_by_invite_token(invite_token)
                if not invite:
                    return _finalize(
                        json_response(404, {"error": "Education invite not found."}),
                        error="not_found",
                    )
                organization = repo.get_organization(str(invite.get("organization_id") or ""))
                return _finalize(
                    json_response(
                        200,
                        {
                            "invite": invite,
                            "organization": {
                                "organization_id": organization.get("organization_id"),
                                "name": organization.get("name"),
                                "plan_code": organization.get("plan_code"),
                            },
                        },
                    )
                )
            if path.endswith("/accept") and method == "POST":
                membership = repo.accept_invite(
                    invite_token,
                    user_id,
                    accepted_email=_user_profile_email(user_id),
                    updated_by_user_id=user_id,
                )
                return _finalize(json_response(200, {"membership": membership}))
            return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
        if path.endswith("/v1/education/me") and method == "GET":
            teacher_org_ids = _education_teacher_organization_ids(snapshot)
            organizations = [
                item
                for item in snapshot.get("organizations") or []
                if str(item.get("organization_id") or "").strip() in teacher_org_ids
            ]
            memberships: list[Dict[str, Any]] = []
            student_usage: list[Dict[str, Any]] = []
            for organization in organizations:
                organization_id = str(organization.get("organization_id") or "")
                memberships.extend(repo.list_memberships(organization_id=organization_id))
                student_usage.extend(repo.list_education_student_usage(organization_id))
            return _finalize(
                json_response(
                    200,
                    {
                        "organizations": organizations,
                        "memberships": memberships,
                        "student_usage": student_usage,
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/education/me/invites") and method == "POST":
            body = parse_json_body(event)
            organization_id = str(body.get("organization_id") or "").strip()
            teacher_org_ids = _education_teacher_organization_ids(snapshot)
            if organization_id not in teacher_org_ids:
                return _finalize(
                    json_response(403, {"error": "Teacher access required."}),
                    error="forbidden",
                )
            membership = repo.save_membership(
                {
                    "organization_id": organization_id,
                    "email": body.get("email") or body.get("student_email"),
                    "role": "student",
                    "status": "pending",
                    "seat_consumed": True,
                },
                updated_by_user_id=user_id,
            )
            organization = repo.get_organization(organization_id)
            email_sent, email_error = _send_education_invite_email(
                membership=membership,
                organization=organization,
                locale=_teacher_locale(user_id),
            )
            response = {"membership": membership, "email_sent": email_sent}
            if email_error:
                response["email_error"] = email_error
            return _finalize(json_response(200, response))
        if path.endswith("/v1/education/me/memberships") and method == "POST":
            body = parse_json_body(event)
            organization_id = str(body.get("organization_id") or "").strip()
            teacher_org_ids = _education_teacher_organization_ids(snapshot)
            if organization_id not in teacher_org_ids:
                return _finalize(
                    json_response(403, {"error": "Teacher access required."}),
                    error="forbidden",
                )
            status = str(body.get("status") or "").strip().lower()
            if status not in {"pending", "active", "inactive", "revoked", "removed"}:
                return _finalize(
                    json_response(400, {"error": "Membership status is invalid."}),
                    error="bad_request",
                )
            target_user_id = str(body.get("user_id") or "").strip()
            if not target_user_id:
                return _finalize(
                    json_response(400, {"error": "Student membership is required."}),
                    error="bad_request",
                )
            existing = repo.get_membership(organization_id, target_user_id)
            if not existing:
                return _finalize(
                    json_response(404, {"error": "Student membership not found."}),
                    error="not_found",
                )
            if str(existing.get("role") or "").strip().lower() != "student":
                return _finalize(
                    json_response(403, {"error": "Only student seats can be changed here."}),
                    error="forbidden",
                )
            membership = repo.save_membership(
                {
                    "organization_id": organization_id,
                    "user_id": target_user_id,
                    "email": existing.get("email") or body.get("email"),
                    "role": "student",
                    "status": status,
                    "seat_consumed": status in {"pending", "active"},
                },
                updated_by_user_id=user_id,
            )
            return _finalize(json_response(200, {"membership": membership}))
        if path.endswith("/v1/organizations/me"):
            return _finalize(
                json_response(
                    200,
                    {
                        "organizations": _enrich_organizations_with_admin_profiles(
                            snapshot.get("organizations") or []
                        ),
                        "memberships": snapshot.get("memberships") or [],
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/workspaces/me"):
            return _finalize(
                json_response(
                    200,
                    {
                        "workspaces": snapshot.get("workspaces") or [],
                        "summary": snapshot.get("summary") or {},
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        if path.endswith("/v1/cloud-projects/me"):
            entitlement = _effective_entitlement_for_cloud(user_id)
            return _finalize(
                json_response(
                    200,
                    {
                        "cloud_projects": _enrich_cloud_projects_with_profiles(
                            snapshot.get("cloud_projects") or []
                        ),
                        "summary": snapshot.get("summary") or {},
                        "storage": _cloud_storage_payload(
                            user_id,
                            entitlement,
                            snapshot=snapshot,
                        ),
                        "configurable": snapshot.get("configurable"),
                    },
                )
            )
        return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
    except RequestBodyError as exc:
        return _finalize(
            json_response(exc.status_code, {"error": exc.message}),
            error="request_body_invalid",
        )
    except PermissionError as exc:
        return _finalize(json_response(403, {"error": str(exc)}), error="forbidden")
    except FileNotFoundError as exc:
        return _finalize(json_response(404, {"error": str(exc)}), error="not_found")
    except ValueError as exc:
        message = str(exc)
        status_code = 409 if "revision conflict" in message.lower() else 400
        error_code = "conflict" if status_code == 409 else "bad_request"
        return _finalize(json_response(status_code, {"error": message}), error=error_code)
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "collaboration"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
