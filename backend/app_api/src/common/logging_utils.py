from __future__ import annotations

import json
import time
from typing import Any, Dict


def build_request_log_context(
    event: Dict[str, Any],
    aws_context: Any,
    *,
    user_id: str = "",
    project_id: str = "",
) -> Dict[str, Any]:
    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    return {
        "request_id": str(
            request_context.get("requestId")
            or event.get("requestId")
            or getattr(aws_context, "aws_request_id", "")
        ).strip(),
        "user_id": user_id,
        "endpoint": str(event.get("rawPath") or event.get("path") or "").strip(),
        "project_id": project_id,
        "method": str(http.get("method") or event.get("httpMethod") or "").strip(),
    }


def log_request_complete(
    started_at: float,
    *,
    status_code: int,
    request_context: Dict[str, Any],
    error: str = "",
) -> None:
    payload = {
        **request_context,
        "status_code": status_code,
        "latency_ms": int((time.perf_counter() - started_at) * 1000),
        "error": error,
    }
    print(
        json.dumps(
            {key: value for key, value in payload.items() if value not in ("", None)},
            default=str,
        )
    )
