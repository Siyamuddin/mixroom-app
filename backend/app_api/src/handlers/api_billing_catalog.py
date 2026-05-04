from __future__ import annotations

import time
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.billing_catalog_repository import BillingCatalogRepository
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = BillingCatalogRepository()
init_sentry("mixroom-app-api-billing-catalog")


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
        catalog = repo.get_catalog()
        catalog["requested_by_user_id"] = user_id
        return _finalize(json_response(200, catalog))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "billing_catalog"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )

