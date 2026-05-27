from __future__ import annotations

import time
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.billing_catalog import (
    catalog_plan_by_code,
    infer_plan_code,
    merge_capabilities,
    merge_limits,
)
from common.billing_catalog_repository import BillingCatalogRepository
from common.collaboration_repository import CollaborationRepository
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry
from common.models import (
    entitlement_capabilities_for_status,
    free_entitlement,
    legacy_tier_for_plan_code,
    normalize_status,
    status_has_active_access,
    subscription_effective_status,
)
from common.repository import BillingRepository

repo = BillingRepository()
catalog_repo = BillingCatalogRepository()
collaboration_repo = CollaborationRepository()
init_sentry("mixroom-app-api-entitlements")


def _empty_collaboration_snapshot() -> Dict[str, Any]:
    return {
        "organizations": [],
        "memberships": [],
        "workspaces": [],
        "cloud_projects": [],
        "summary": {
            "organization_count": 0,
            "workspace_count": 0,
            "cloud_project_count": 0,
        },
    }


def _safe_collaboration_snapshot(user_id: str) -> Dict[str, Any]:
    try:
        return collaboration_repo.build_user_access_snapshot(user_id)
    except Exception as exc:
        capture_exception(
            exc,
            tags={
                "service": "subscriptions_entitlements",
                "dependency": "collaboration",
            },
        )
        return _empty_collaboration_snapshot()


def _coerce_bool_map(raw: Any) -> Dict[str, bool]:
    if not isinstance(raw, dict):
        return {}
    return {
        str(key).strip(): bool(value)
        for key, value in raw.items()
        if str(key).strip()
    }


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


def _active_org_access(
    snapshot: Dict[str, Any],
    catalog: Dict[str, Any],
) -> tuple[Dict[str, bool], Dict[str, Any], list[Dict[str, Any]], list[Dict[str, Any]]]:
    capabilities: Dict[str, bool] = {}
    limits: Dict[str, Any] = {}
    access_sources: list[Dict[str, Any]] = []
    organizations: list[Dict[str, Any]] = []
    for organization in snapshot.get("organizations") or []:
        org_status = str(organization.get("status") or "").strip().lower()
        org_is_active = org_status in {"active", "past_due"}
        org_is_visible = org_is_active or org_status in {"locked", "suspended"}
        if not org_is_visible:
            continue
        if str(organization.get("membership_status") or "").strip().lower() != "active":
            continue
        plan_code = str(organization.get("plan_code") or "").strip().lower() or infer_plan_code("")
        plan = catalog_plan_by_code(plan_code, catalog=catalog)
        membership_role = str(organization.get("membership_role") or "").strip().lower()
        grants_personal_entitlement = plan_code != "education" or membership_role == "student"
        if org_is_active and grants_personal_entitlement:
            capabilities = merge_capabilities(capabilities, plan.get("capabilities") or {})
            limits = merge_limits(limits, plan.get("limits") or {})
            access_sources.append(
                {
                    "source_type": "organization",
                    "organization_id": organization.get("organization_id"),
                    "organization_name": organization.get("name"),
                    "role": membership_role or organization.get("membership_role"),
                    "plan_code": plan.get("code"),
                    "plan_label": plan.get("label"),
                    "plan_group": plan.get("group"),
                    "seat_limit": organization.get("seat_limit"),
                }
            )
        organizations.append(
            {
                "organization_id": organization.get("organization_id"),
                "name": organization.get("name"),
                "plan_code": plan.get("code"),
                "plan_label": plan.get("label"),
                "plan_group": plan.get("group"),
                "role": organization.get("membership_role"),
                "status": organization.get("status"),
                "membership_status": organization.get("membership_status"),
                "seat_limit": organization.get("seat_limit"),
                "seats_used": organization.get("seats_used"),
                "seats_active": organization.get("seats_active"),
                "seats_invited": organization.get("seats_invited"),
                "seats_available": organization.get("seats_available"),
                "shared_workspace_enabled": organization.get("shared_workspace_enabled"),
                "support_notes": organization.get("support_notes"),
                "can_write": organization.get("can_write"),
                "access_status": organization.get("access_status"),
                "locked_at": organization.get("locked_at"),
                "retention_expires_at": organization.get("retention_expires_at"),
            }
        )
    return capabilities, limits, access_sources, organizations


def _normalize_entitlement(raw: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    catalog = catalog_repo.get_catalog()
    collaboration = _safe_collaboration_snapshot(user_id)
    personal_status = subscription_effective_status(raw)
    personal_plan_code = infer_plan_code(raw.get("plan_code") or raw.get("tier") or "")
    personal_plan = catalog_plan_by_code(personal_plan_code, catalog=catalog)
    free_plan = catalog_plan_by_code("free", catalog=catalog)
    personal_active = status_has_active_access(personal_status)

    personal_capabilities = _coerce_bool_map(raw.get("capabilities"))
    if not personal_capabilities or not personal_active:
        personal_capabilities = entitlement_capabilities_for_status(
            personal_plan_code,
            personal_status,
        )
    personal_capabilities = merge_capabilities(
        personal_plan.get("capabilities") or {},
        personal_capabilities,
    )
    effective_capabilities = merge_capabilities(free_plan.get("capabilities") or {})
    effective_limits = merge_limits(free_plan.get("limits") or {})
    access_sources = []
    effective_plan = free_plan
    effective_status = "active"
    effective_source_provider = "admin_grant"
    effective_source_subscription_id = "free-default"
    effective_management_channel = "free"
    effective_expires_at = None
    effective_product_code = ""
    effective_next_billed_at = None
    effective_seat_count = None
    effective_extra_storage_tb = 0

    if personal_active:
        effective_plan = personal_plan
        effective_status = personal_status
        effective_source_provider = raw.get("source_provider") or "admin_grant"
        effective_source_subscription_id = (
            raw.get("source_subscription_id") or "free-default"
        )
        effective_management_channel = raw.get("management_channel") or "free"
        effective_expires_at = raw.get("expires_at")
        effective_product_code = raw.get("product_code") or ""
        effective_next_billed_at = raw.get("next_billed_at")
        effective_seat_count = raw.get("seat_count")
        effective_extra_storage_tb = raw.get("extra_storage_tb") or 0
        effective_capabilities = merge_capabilities(
            effective_capabilities,
            personal_capabilities,
        )
        effective_limits = merge_limits(
            effective_limits,
            personal_plan.get("limits") or {},
            _explicit_limit_overrides(raw),
        )
        access_sources.append(
            {
                "source_type": "personal",
                "plan_code": personal_plan.get("code"),
                "plan_label": personal_plan.get("label"),
                "plan_group": personal_plan.get("group"),
                "status": personal_status,
                "source_provider": raw.get("source_provider") or "admin_grant",
                "source_subscription_id": raw.get("source_subscription_id") or "free-default",
                "management_channel": raw.get("management_channel") or "free",
                "product_code": raw.get("product_code") or "",
                "next_billed_at": raw.get("next_billed_at"),
                "seat_count": raw.get("seat_count"),
                "extra_storage_tb": raw.get("extra_storage_tb") or 0,
            }
        )

    org_capabilities, org_limits, org_access_sources, organizations = _active_org_access(
        collaboration,
        catalog,
    )
    effective_capabilities = merge_capabilities(
        effective_capabilities,
        org_capabilities,
    )
    effective_limits = merge_limits(
        effective_limits,
        org_limits,
    )
    access_sources.extend(org_access_sources)
    for source in org_access_sources:
        source_plan = catalog_plan_by_code(source.get("plan_code") or "", catalog=catalog)
        if _plan_rank(source_plan) > _plan_rank(effective_plan):
            effective_plan = source_plan
            effective_status = "active"
            effective_source_provider = "admin_grant"
            effective_source_subscription_id = (
                source.get("organization_id") or effective_source_subscription_id
            )
            effective_management_channel = "admin"
            effective_expires_at = None
            effective_product_code = ""
            effective_next_billed_at = None
            effective_seat_count = source.get("seat_limit")
            effective_extra_storage_tb = 0

    snapshot = {
        "user_id": user_id,
        "tier": legacy_tier_for_plan_code(effective_plan.get("code")),
        "status": normalize_status(effective_status),
        "effective_at": raw.get("effective_at"),
        "expires_at": effective_expires_at,
        "source_provider": effective_source_provider,
        "source_subscription_id": effective_source_subscription_id,
        "capabilities": effective_capabilities,
        "management_channel": effective_management_channel,
        "revision": int(raw.get("revision") or 0),
        "plan_code": effective_plan.get("code"),
        "plan_label": effective_plan.get("label"),
        "plan_group": effective_plan.get("group"),
        "product_code": effective_product_code,
        "next_billed_at": effective_next_billed_at,
        "seat_count": effective_seat_count,
        "extra_storage_tb": effective_extra_storage_tb,
        "paddle_subscription_id": (
            effective_source_subscription_id
            if str(effective_source_provider or "").strip().lower() == "paddle"
            else ""
        ),
        "limits": effective_limits,
        "access_sources": access_sources,
        "workspace_access_summary": collaboration.get("summary") or {},
        "organizations": organizations,
        "billing_support": catalog.get("support") or {},
    }
    return snapshot


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
        existing = repo.get_entitlement(user_id)
        if not existing:
            default_snapshot = free_entitlement(
                user_id=user_id,
            ).to_dict()
            repo.put_entitlement(default_snapshot)
            return _finalize(
                json_response(200, _normalize_entitlement(default_snapshot, user_id))
            )

        return _finalize(json_response(200, _normalize_entitlement(existing, user_id)))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "subscriptions_entitlements"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
