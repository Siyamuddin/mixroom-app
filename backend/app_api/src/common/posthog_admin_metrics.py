from __future__ import annotations

import copy
import json
import time
from datetime import datetime, timezone
from typing import Any, Dict, List

import urllib.error
import urllib.request

from . import config
from .secrets import load_posthog_personal_api_key

_ACTIVE_USER_EVENT = "$screen"
_TREND_RANGE_DAYS = 365


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _safe_float(value: Any) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


class PosthogAdminMetricsClient:
    def __init__(self) -> None:
        self._cache: tuple[float, Dict[str, Any]] | None = None

    def fetch(self) -> Dict[str, Any]:
        cached = self._get_cached()
        if cached is not None:
            return cached

        if not config.POSTHOG_PROJECT_ID:
            payload = self._base_payload(
                status="unconfigured",
                note="PostHog project is not configured.",
            )
            self._set_cached(payload)
            return payload

        try:
            api_key = load_posthog_personal_api_key()
        except Exception as exc:
            payload = self._base_payload(
                status="unconfigured",
                note=str(exc),
            )
            self._set_cached(payload)
            return payload

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        payload = self._base_payload(status="live")
        payload["metrics"] = {
            "dau": self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 1 DAY"
                ),
            ),
            "wau": self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 7 DAY"
                ),
            ),
            "mau": self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 30 DAY"
                ),
            ),
            "hours_24h": round(
                self._query_scalar(
                    headers,
                    (
                        "SELECT sum(toFloat(properties.duration_ms)) / 3600000 AS value "
                        "FROM events "
                        "WHERE event = 'session_ended' "
                        "AND timestamp >= now() - INTERVAL 1 DAY"
                    ),
                    numeric_type="float",
                ),
                1,
            ),
        }
        payload["daily_active_users"] = self._query_rows(
            headers,
            (
                "SELECT toDate(timestamp) AS day, count(DISTINCT person_id) AS active_users "
                "FROM events "
                f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                "AND person_id IS NOT NULL "
                f"AND timestamp >= now() - INTERVAL {_TREND_RANGE_DAYS} DAY "
                "GROUP BY day "
                "ORDER BY day ASC"
            ),
        )
        payload["daily_hours_used"] = self._query_rows(
            headers,
            (
                "SELECT toDate(timestamp) AS day, "
                "round(sum(toFloat(properties.duration_ms)) / 3600000, 2) AS hours_used "
                "FROM events "
                "WHERE event = 'session_ended' "
                f"AND timestamp >= now() - INTERVAL {_TREND_RANGE_DAYS} DAY "
                "GROUP BY day "
                "ORDER BY day ASC"
            ),
        )
        payload["top_countries"] = self._query_rows(
            headers,
            (
                "SELECT coalesce(nullIf(properties.$geoip_country_name, ''), 'Unknown') AS country, "
                "count(DISTINCT person_id) AS users "
                "FROM events "
                f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                "AND person_id IS NOT NULL "
                "AND timestamp >= now() - INTERVAL 30 DAY "
                "GROUP BY country "
                "ORDER BY users DESC "
                "LIMIT 8"
            ),
        )
        payload["updated_at"] = _utc_now_iso()
        self._set_cached(payload)
        return copy.deepcopy(payload)

    def _post_query(self, headers: Dict[str, str], query: str) -> Dict[str, Any]:
        host = config.POSTHOG_APP_HOST.rstrip("/")
        url = f"{host}/api/projects/{config.POSTHOG_PROJECT_ID}/query/"
        request = urllib.request.Request(
            url,
            data=json.dumps(
                {
                    "refresh": "blocking",
                    "query": {
                        "kind": "HogQLQuery",
                        "query": query,
                    },
                }
            ).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(
                request,
                timeout=config.HTTP_TIMEOUT_SECONDS,
            ) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise ValueError(
                f"PostHog query failed with status {exc.code}: {detail}"
            ) from exc
        except urllib.error.URLError as exc:
            raise ValueError(f"PostHog query failed: {exc}") from exc

        payload = json.loads(raw.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("PostHog query returned a non-object response.")
        return payload

    def _query_scalar(
        self,
        headers: Dict[str, str],
        query: str,
        *,
        numeric_type: str = "int",
    ) -> int | float:
        rows = self._query_rows(headers, query)
        if not rows:
            return 0.0 if numeric_type == "float" else 0
        first_row = rows[0]
        first_value = next(iter(first_row.values()), 0)
        if numeric_type == "float":
            return _safe_float(first_value)
        return _safe_int(first_value)

    def _query_rows(self, headers: Dict[str, str], query: str) -> List[Dict[str, Any]]:
        payload = self._post_query(headers, query)
        results = payload.get("results")
        if not isinstance(results, list):
            return []
        if not results:
            return []
        if isinstance(results[0], dict):
            return [dict(item) for item in results if isinstance(item, dict)]

        columns = payload.get("columns")
        if not isinstance(columns, list):
            return []

        rows: List[Dict[str, Any]] = []
        for row in results:
            if not isinstance(row, list):
                continue
            mapped: Dict[str, Any] = {}
            for index, column in enumerate(columns):
                mapped[_safe_str(column)] = row[index] if index < len(row) else None
            rows.append(mapped)
        return rows

    def _base_payload(self, *, status: str, note: str = "") -> Dict[str, Any]:
        payload = {
            "source": "posthog",
            "status": status,
            "updated_at": "",
            "metrics": {
                "dau": 0,
                "wau": 0,
                "mau": 0,
                "hours_24h": 0.0,
            },
            "daily_active_users": [],
            "daily_hours_used": [],
            "top_countries": [],
        }
        if note:
            payload["note"] = note
        return payload

    def _cache_ttl_seconds(self) -> int:
        return max(60, config.POSTHOG_METRICS_CACHE_TTL_SECONDS)

    def _get_cached(self) -> Dict[str, Any] | None:
        cached = self._cache
        now = time.time()
        if cached and now - cached[0] < self._cache_ttl_seconds():
            return copy.deepcopy(cached[1])
        return None

    def _set_cached(self, payload: Dict[str, Any]) -> None:
        self._cache = (time.time(), copy.deepcopy(payload))
