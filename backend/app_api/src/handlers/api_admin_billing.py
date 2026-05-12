from __future__ import annotations

import time
from typing import Any, Dict

from common import config
from common.admin_access_repository import AdminAccessRepository
from common.auth import extract_claims_from_event, json_response, unauthorized
from common.billing_catalog_repository import BillingCatalogRepository
from common.collaboration_repository import CollaborationRepository
from common.events import RequestBodyError, parse_json_body
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

catalog_repo = BillingCatalogRepository()
collaboration_repo = CollaborationRepository()
access_repo = AdminAccessRepository()
init_sentry("mixroom-app-api-admin-billing")


def _path(event: Dict[str, Any]) -> str:
    return str(event.get("rawPath") or event.get("path") or "")


def _method(event: Dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http = (request_context.get("http") or {}) if isinstance(request_context, dict) else {}
    method = http.get("method") or event.get("httpMethod") or ""
    return str(method).upper()


def _admin_identity(event: Dict[str, Any]) -> tuple[str, str, str]:
    admin_client_id = (
        config.ADMIN_COGNITO_APP_CLIENT_ID or config.COGNITO_APP_CLIENT_ID
    ).strip()
    admin_user_pool_id = (
        config.ADMIN_COGNITO_USER_POOL_ID or config.COGNITO_USER_POOL_ID
    ).strip()
    try:
        claims = extract_claims_from_event(
            event,
            audiences=[admin_client_id],
            user_pool_ids=[admin_user_pool_id],
            allow_native=False,
            allow_cognito=True,
        )
    except TypeError:
        claims = extract_claims_from_event(
            event,
            audiences=[admin_client_id],
            user_pool_ids=[admin_user_pool_id],
        )
    user_id = str(claims.get("sub") or "").strip()
    email = str(claims.get("email") or "").strip().lower()
    return admin_client_id if admin_user_pool_id else "", user_id, email


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    started_at = time.perf_counter()
    admin_client_id, admin_user_id, admin_email = _admin_identity(event)
    request_context = build_request_log_context(event, _context, user_id=admin_user_id)

    def _finalize(response: Dict[str, Any], *, error: str = "") -> Dict[str, Any]:
        log_request_complete(
            started_at,
            status_code=int(response.get("statusCode") or 500),
            request_context=request_context,
            error=error,
        )
        return response

    if not admin_client_id:
        return _finalize(json_response(404, {"error": "Not found"}), error="disabled")

    if not admin_user_id or not admin_email:
        return _finalize(
            unauthorized("Employee sign-in required."),
            error="unauthorized",
        )

    if not access_repo.is_email_allowed(admin_email):
        return _finalize(
            json_response(403, {"error": "Email is not allowlisted for admin access."}),
            error="not_allowlisted",
        )

    path = _path(event)
    method = _method(event)
    query = event.get("queryStringParameters") or {}
    try:
        if path.endswith("/v1/internal/admin/settings/billing-catalog"):
            if method == "GET":
                payload = catalog_repo.get_catalog()
                payload["requested_by"] = admin_user_id
                payload["requested_email"] = admin_email
                return _finalize(json_response(200, payload))
            if method == "PUT":
                body = parse_json_body(event)
                payload = catalog_repo.replace_catalog(
                    plans=body.get("plans"),
                    products=body.get("products"),
                    provider_products=body.get("provider_products"),
                    offers=body.get("offers"),
                    support=body.get("support"),
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                payload["updated_by"] = admin_user_id
                payload["updated_email"] = admin_email
                return _finalize(json_response(200, payload))

        if path.endswith("/v1/internal/admin/billing/organizations"):
            if method == "GET":
                payload = {
                    "organizations": collaboration_repo.list_organizations(),
                    "configurable": collaboration_repo.is_configured(),
                    "requested_by": admin_user_id,
                    "requested_email": admin_email,
                }
                return _finalize(json_response(200, payload))
            if method == "POST":
                body = parse_json_body(event)
                organization = collaboration_repo.save_organization(
                    body,
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                return _finalize(json_response(200, {"organization": organization}))

        if path.endswith("/v1/internal/admin/billing/education-provisioning"):
            if method == "POST":
                body = parse_json_body(event)
                payload = collaboration_repo.provision_education_organization(
                    body,
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                return _finalize(json_response(200, payload))

        if path.endswith("/v1/internal/admin/billing/memberships"):
            if method == "GET":
                payload = {
                    "memberships": collaboration_repo.list_memberships(
                        user_id=str((query.get("user_id") if isinstance(query, dict) else "") or ""),
                        organization_id=str(
                            (query.get("organization_id") if isinstance(query, dict) else "") or ""
                        ),
                    ),
                    "configurable": collaboration_repo.is_configured(),
                    "requested_by": admin_user_id,
                    "requested_email": admin_email,
                }
                return _finalize(json_response(200, payload))
            if method == "POST":
                body = parse_json_body(event)
                membership = collaboration_repo.save_membership(
                    body,
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                return _finalize(json_response(200, {"membership": membership}))

        if path.endswith("/v1/internal/admin/billing/workspaces"):
            if method == "GET":
                payload = {
                    "workspaces": collaboration_repo.list_workspaces(
                        organization_id=str(
                            (query.get("organization_id") if isinstance(query, dict) else "") or ""
                        ),
                        user_id=str((query.get("user_id") if isinstance(query, dict) else "") or ""),
                    ),
                    "configurable": collaboration_repo.is_configured(),
                    "requested_by": admin_user_id,
                    "requested_email": admin_email,
                }
                return _finalize(json_response(200, payload))
            if method == "POST":
                body = parse_json_body(event)
                workspace = collaboration_repo.save_workspace(
                    body,
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                return _finalize(json_response(200, {"workspace": workspace}))

        if path.endswith("/v1/internal/admin/billing/cloud-projects"):
            if method == "GET":
                payload = {
                    "cloud_projects": collaboration_repo.list_cloud_projects(
                        workspace_id=str(
                            (query.get("workspace_id") if isinstance(query, dict) else "") or ""
                        ),
                        organization_id=str(
                            (query.get("organization_id") if isinstance(query, dict) else "") or ""
                        ),
                        user_id=str((query.get("user_id") if isinstance(query, dict) else "") or ""),
                    ),
                    "configurable": collaboration_repo.is_configured(),
                    "requested_by": admin_user_id,
                    "requested_email": admin_email,
                }
                return _finalize(json_response(200, payload))
            if method == "POST":
                body = parse_json_body(event)
                cloud_project = collaboration_repo.save_cloud_project(
                    body,
                    updated_by_user_id=admin_user_id,
                    updated_by_email=admin_email,
                )
                return _finalize(json_response(200, {"cloud_project": cloud_project}))
    except RequestBodyError as exc:
        return _finalize(
            json_response(exc.status_code, {"error": exc.message}),
            error="request_body_invalid",
        )
    except ValueError as exc:
        return _finalize(json_response(400, {"error": str(exc)}), error="bad_request")
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "admin_billing"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )

    return _finalize(json_response(404, {"error": "Not found"}), error="not_found")
