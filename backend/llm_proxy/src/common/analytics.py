from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

from . import config

try:
    import posthog
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    posthog = None

_configured = False


def analytics_enabled_from_body(body: Dict[str, Any]) -> bool:
    raw = body.get("analytics_enabled")
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, str):
        return raw.strip().lower() != "false"
    return True


def client_context_from_body(body: Dict[str, Any]) -> Dict[str, Any]:
    raw = body.get("client_context")
    if isinstance(raw, dict):
        return {str(key): value for key, value in raw.items()}
    return {}


def build_event_properties(
    *,
    user_id: str,
    client_context: Dict[str, Any] | None = None,
    extra: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    context = client_context or {}
    props: Dict[str, Any] = {
        "user_id": user_id,
        "distinct_id": str(context.get("distinct_id") or user_id).strip() or user_id,
        "device_id": str(context.get("device_id") or "").strip(),
        "session_id": str(context.get("session_id") or "").strip(),
        "app_version": str(context.get("app_version") or "").strip(),
        "platform": str(context.get("platform") or "").strip(),
        "environment": str(context.get("environment") or config.ENVIRONMENT).strip(),
        "locale": str(context.get("locale") or "").strip(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if extra:
        props.update(extra)

    return {
        key: value
        for key, value in props.items()
        if value is not None and (not isinstance(value, str) or value.strip())
    }


def capture_event(
    event_name: str,
    *,
    distinct_id: str,
    properties: Dict[str, Any],
    enabled: bool,
) -> None:
    if not enabled or not distinct_id:
        return
    if posthog is None:
        return
    if not _ensure_configured():
        return

    try:
        posthog.capture(
            event_name,
            distinct_id=distinct_id,
            properties=properties,
        )
        if hasattr(posthog, "shutdown"):
            posthog.shutdown()
    except Exception:
        return


def _ensure_configured() -> bool:
    global _configured
    if _configured:
        return True
    if posthog is None:
        return False
    if not config.POSTHOG_API_KEY or not config.POSTHOG_HOST:
        return False

    posthog.project_api_key = config.POSTHOG_API_KEY
    posthog.host = config.POSTHOG_HOST.rstrip("/")
    _configured = True
    return True
