from __future__ import annotations

from typing import Any, Dict

from . import config

try:
    import sentry_sdk
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    sentry_sdk = None

_initialized = False


def init_sentry(service_name: str) -> None:
    global _initialized
    if _initialized:
        return
    if sentry_sdk is None or not config.SENTRY_DSN:
        return

    sentry_sdk.init(
        dsn=config.SENTRY_DSN,
        environment=config.ENVIRONMENT,
        server_name=service_name,
        traces_sample_rate=0.0,
        profiles_sample_rate=0.0,
    )
    _initialized = True


def capture_exception(
    error: Exception,
    *,
    context: Dict[str, Any] | None = None,
    tags: Dict[str, str] | None = None,
) -> None:
    if sentry_sdk is None or not _initialized:
        return

    with sentry_sdk.push_scope() as scope:
        for key, value in (tags or {}).items():
            if value:
                scope.set_tag(key, value)
        if context:
            scope.set_context("mixroom", context)
        sentry_sdk.capture_exception(error)
