from __future__ import annotations

import time
from typing import Any, Dict

from common.auth import extract_user_id_from_event, json_response, unauthorized
from common.feature_flags import FeatureFlagsRepository
from common.logging_utils import build_request_log_context, log_request_complete
from common.monitoring import capture_exception, init_sentry

repo = FeatureFlagsRepository()
init_sentry("mixroom-app-api-feature-flags")


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
        payload = repo.get_flags()
        payload["requested_by_user_id"] = user_id
        return _finalize(json_response(200, payload))
    except Exception as exc:
        capture_exception(
            exc,
            context=request_context,
            tags={"service": "feature_flags"},
        )
        return _finalize(
            json_response(500, {"error": "Internal server error"}),
            error="internal_server_error",
        )
