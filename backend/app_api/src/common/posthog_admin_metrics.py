from __future__ import annotations

import copy
import json
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List

import urllib.error
import urllib.request

from . import config
from .secrets import load_posthog_personal_api_key

_ACTIVE_USER_EVENT = "$screen"
_TREND_RANGE_DAYS = 365
_AI_OBSERVABILITY_RANGE_DAYS = 30
_LIVE_PRESENCE_WINDOW_MINUTES = 5
_TOOL_USAGE_RANGE_OPTIONS = {
    "7d": ("Weekly", "timestamp >= now() - INTERVAL 7 DAY"),
    "30d": ("Monthly", "timestamp >= now() - INTERVAL 30 DAY"),
    "all": ("All time", ""),
}
_USER_TYPE_EXPR = (
    "coalesce(nullIf(properties.user_type, ''), nullIf(properties.music_profile, ''), 'unknown')"
)


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
        self._cache: dict[str, tuple[float, Dict[str, Any]]] = {}

    def fetch(self, *, tool_usage_range_key: str = "30d") -> Dict[str, Any]:
        normalized_tool_range = self._normalize_tool_usage_range_key(tool_usage_range_key)
        cache_key = f"dashboard:{normalized_tool_range}"
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        product_metrics = self.fetch_product_metrics(tool_usage_range_key=normalized_tool_range)
        ai_observability = self.fetch_ai_observability(
            tool_usage_range_key=normalized_tool_range
        )
        payload = {
            **product_metrics,
            "ai_observability": {
                key: value
                for key, value in ai_observability.items()
                if key not in {"source", "status", "note", "updated_at"}
            },
            "updated_at": _utc_now_iso(),
        }
        self._set_cached(cache_key, payload)
        return copy.deepcopy(payload)

    def fetch_product_metrics(self, *, tool_usage_range_key: str = "30d") -> Dict[str, Any]:
        normalized_tool_range = self._normalize_tool_usage_range_key(tool_usage_range_key)
        cache_key = f"product:{normalized_tool_range}"
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        try:
            headers = self._build_headers()
        except Exception as exc:
            payload = self._base_payload(
                status="unconfigured",
                note=str(exc),
                tool_usage_range_key=normalized_tool_range,
            )
            self._set_cached(cache_key, payload)
            return payload

        payload = self._base_payload(status="live", tool_usage_range_key=normalized_tool_range)
        tasks = {
            "dau": lambda: self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 1 DAY"
                ),
            ),
            "wau": lambda: self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 7 DAY"
                ),
            ),
            "mau": lambda: self._query_scalar(
                headers,
                (
                    "SELECT count(DISTINCT person_id) AS value "
                    "FROM events "
                    f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                    "AND person_id IS NOT NULL "
                    "AND timestamp >= now() - INTERVAL 30 DAY"
                ),
            ),
            "hours_24h": lambda: round(
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
            "daily_active_users": lambda: self._query_rows(
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
            ),
            "daily_hours_used": lambda: self._query_rows(
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
            ),
            "top_countries": lambda: self._query_rows(
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
            ),
        }
        results = self._run_tasks(tasks)
        payload["metrics"] = {
            "dau": results["dau"],
            "wau": results["wau"],
            "mau": results["mau"],
            "hours_24h": results["hours_24h"],
        }
        payload["daily_active_users"] = results["daily_active_users"]
        payload["daily_hours_used"] = results["daily_hours_used"]
        payload["top_countries"] = results["top_countries"]
        payload["updated_at"] = _utc_now_iso()
        self._set_cached(cache_key, payload)
        return copy.deepcopy(payload)

    def fetch_live_presence(self) -> Dict[str, Any]:
        cache_key = "live_presence"
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        try:
            headers = self._build_headers()
        except Exception as exc:
            payload = {
                "source": "posthog",
                "status": "unconfigured",
                "active_users": 0,
                "window_minutes": _LIVE_PRESENCE_WINDOW_MINUTES,
                "updated_at": "",
                "note": str(exc),
            }
            self._set_cached(cache_key, payload)
            return copy.deepcopy(payload)

        try:
            active_users = self._live_presence_active_user_count(headers)
        except Exception as exc:
            payload = {
                "source": "posthog",
                "status": "error",
                "active_users": 0,
                "window_minutes": _LIVE_PRESENCE_WINDOW_MINUTES,
                "updated_at": _utc_now_iso(),
                "note": str(exc),
            }
            self._set_cached(cache_key, payload)
            return copy.deepcopy(payload)

        payload = {
            "source": "posthog",
            "status": "live",
            "active_users": active_users,
            "window_minutes": _LIVE_PRESENCE_WINDOW_MINUTES,
            "updated_at": _utc_now_iso(),
        }
        self._set_cached(cache_key, payload)
        return copy.deepcopy(payload)

    def _live_presence_active_user_count(self, headers: Dict[str, str]) -> int:
        live_presence_timeout = max(3, min(6, config.HTTP_TIMEOUT_SECONDS))
        rows = self._query_rows(
            headers,
            (
                "SELECT DISTINCT person_id AS person_id "
                "FROM events "
                f"WHERE event = '{_ACTIVE_USER_EVENT}' "
                "AND person_id IS NOT NULL "
                f"AND timestamp >= now() - INTERVAL {_LIVE_PRESENCE_WINDOW_MINUTES} MINUTE "
                "LIMIT 1000"
            ),
            timeout_seconds=live_presence_timeout,
        )
        return len(rows)

    def fetch_ai_observability(
        self,
        *,
        tool_usage_range_key: str = "30d",
    ) -> Dict[str, Any]:
        normalized_tool_range = self._normalize_tool_usage_range_key(tool_usage_range_key)
        cache_key = f"observability:{normalized_tool_range}"
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        try:
            headers = self._build_headers()
        except Exception as exc:
            payload = self._base_ai_observability_payload(
                status="unconfigured",
                note=str(exc),
                tool_usage_range_key=normalized_tool_range,
            )
            self._set_cached(cache_key, payload)
            return payload

        payload = self._base_ai_observability_payload(
            status="live",
            tool_usage_range_key=normalized_tool_range,
        )
        tasks = {
            "prompt_cycle_total_ms": lambda: self._query_percentiles(
                headers,
                event_name="ai_prompt_cycle_completed",
                property_name="prompt_cycle_total_ms",
            ),
            "project_stats_ms": lambda: self._query_percentiles(
                headers,
                event_name="ai_prompt_cycle_completed",
                property_name="project_stats_ms",
            ),
            "proxy_roundtrip_ms": lambda: self._query_percentiles(
                headers,
                event_name="ai_prompt_cycle_completed",
                property_name="proxy_roundtrip_ms",
            ),
            "openai_api_ms": lambda: self._query_percentiles(
                headers,
                event_name="ai_prompt_cycle_completed",
                property_name="openai_api_ms",
            ),
            "mix_model_onnx_ms": lambda: self._query_percentiles(
                headers,
                event_name="ai_prompt_cycle_completed",
                property_name="mix_model_onnx_ms",
            ),
            "runtime_success": lambda: self._query_rows(
                headers,
                (
                    "SELECT "
                    "coalesce(nullIf(properties.runtime_config_fingerprint, ''), 'unknown') AS runtime_config_fingerprint, "
                    "countIf(event = 'ai_prompt_cycle_completed') AS successes, "
                    "countIf(event = 'ai_prompt_cycle_failed') AS failures, "
                    "round(100.0 * countIf(event = 'ai_prompt_cycle_completed') / greatest(count(), 1), 1) AS success_rate "
                    "FROM events "
                    "WHERE event IN ('ai_prompt_cycle_completed', 'ai_prompt_cycle_failed') "
                    f"AND timestamp >= now() - INTERVAL {_AI_OBSERVABILITY_RANGE_DAYS} DAY "
                    "GROUP BY runtime_config_fingerprint "
                    "ORDER BY (successes + failures) DESC "
                    "LIMIT 8"
                ),
            ),
            "magnitude_model_usage": lambda: self._query_rows(
                headers,
                (
                    "SELECT "
                    "coalesce(nullIf(properties.mix_magnitude_model_bundle_version, ''), 'unknown') AS bundle_version, "
                    "coalesce(nullIf(properties.mix_magnitude_model_source, ''), 'unknown') AS source, "
                    "count() AS count "
                    "FROM events "
                    "WHERE event = 'ai_prompt_cycle_completed' "
                    f"AND timestamp >= now() - INTERVAL {_AI_OBSERVABILITY_RANGE_DAYS} DAY "
                    "GROUP BY bundle_version, source "
                    "ORDER BY count DESC "
                    "LIMIT 10"
                ),
            ),
            "magnitude_model_updates": lambda: self._query_rows(
                headers,
                (
                    "SELECT "
                    "coalesce(nullIf(properties.status, ''), 'unknown') AS status, "
                    "coalesce(nullIf(properties.mix_magnitude_model_bundle_version, ''), 'unknown') AS bundle_version, "
                    "count() AS count "
                    "FROM events "
                    "WHERE event = 'ai_magnitude_model_update' "
                    f"AND timestamp >= now() - INTERVAL {_AI_OBSERVABILITY_RANGE_DAYS} DAY "
                    "GROUP BY status, bundle_version "
                    "ORDER BY count DESC "
                    "LIMIT 12"
                ),
            ),
            "prompt_tool_usage": lambda: self._query_rows(
                headers,
                self._prompt_tool_usage_query(normalized_tool_range),
            ),
            "export_usage_totals": lambda: self._query_rows(
                headers,
                self._export_usage_totals_query(normalized_tool_range),
            ),
            "export_usage_by_user_type": lambda: self._query_rows(
                headers,
                self._export_usage_by_user_type_query(normalized_tool_range),
            ),
            "ai_prompt_usage_totals": lambda: self._query_rows(
                headers,
                self._ai_prompt_usage_totals_query(normalized_tool_range),
            ),
            "ai_response_usage_totals": lambda: self._query_rows(
                headers,
                self._ai_response_usage_totals_query(normalized_tool_range),
            ),
            "ai_prompt_usage_by_user_type": lambda: self._query_rows(
                headers,
                self._ai_prompt_usage_by_user_type_query(normalized_tool_range),
            ),
            "ai_response_usage_by_user_type": lambda: self._query_rows(
                headers,
                self._ai_response_usage_by_user_type_query(normalized_tool_range),
            ),
        }
        results = self._run_tasks(tasks)
        payload["timings"] = {
            "prompt_cycle_total_ms": results["prompt_cycle_total_ms"],
            "project_stats_ms": results["project_stats_ms"],
            "proxy_roundtrip_ms": results["proxy_roundtrip_ms"],
            "openai_api_ms": results["openai_api_ms"],
            "mix_model_onnx_ms": results["mix_model_onnx_ms"],
        }
        payload["runtime_success"] = results["runtime_success"]
        payload["magnitude_model_usage"] = results["magnitude_model_usage"]
        payload["magnitude_model_updates"] = results["magnitude_model_updates"]
        payload["prompt_tool_usage"] = results["prompt_tool_usage"]
        export_totals_rows = (
            results["export_usage_totals"]
            if isinstance(results["export_usage_totals"], list)
            else []
        )
        export_totals = (
            export_totals_rows[0]
            if export_totals_rows and isinstance(export_totals_rows[0], dict)
            else {}
        )
        export_total_count = _safe_int(export_totals.get("exports_total"))
        export_total_users = _safe_int(export_totals.get("users"))
        payload["export_usage"] = {
            "totals": {
                "exports_total": export_total_count,
                "exports_wav": _safe_int(export_totals.get("exports_wav")),
                "exports_mp3": _safe_int(export_totals.get("exports_mp3")),
                "users": export_total_users,
                "avg_exports_per_user": round(
                    (export_total_count / export_total_users) if export_total_users > 0 else 0.0,
                    2,
                ),
            },
            "by_user_type": [
                {
                    "user_type": _safe_str(row.get("user_type")) or "unknown",
                    "exports_total": _safe_int(row.get("exports_total")),
                    "exports_wav": _safe_int(row.get("exports_wav")),
                    "exports_mp3": _safe_int(row.get("exports_mp3")),
                    "users": _safe_int(row.get("users")),
                    "avg_exports_per_user": round(
                        (
                            _safe_int(row.get("exports_total")) / _safe_int(row.get("users"))
                            if _safe_int(row.get("users")) > 0
                            else 0.0
                        ),
                        2,
                    ),
                }
                for row in (
                    results["export_usage_by_user_type"]
                    if isinstance(results["export_usage_by_user_type"], list)
                    else []
                )
                if isinstance(row, dict)
            ],
        }
        ai_prompt_totals_rows = (
            results["ai_prompt_usage_totals"]
            if isinstance(results["ai_prompt_usage_totals"], list)
            else []
        )
        ai_prompt_totals = (
            ai_prompt_totals_rows[0]
            if ai_prompt_totals_rows and isinstance(ai_prompt_totals_rows[0], dict)
            else {}
        )
        ai_response_totals_rows = (
            results["ai_response_usage_totals"]
            if isinstance(results["ai_response_usage_totals"], list)
            else []
        )
        ai_response_totals = (
            ai_response_totals_rows[0]
            if ai_response_totals_rows and isinstance(ai_response_totals_rows[0], dict)
            else {}
        )
        ai_prompts_total = _safe_int(ai_prompt_totals.get("prompts_total"))
        ai_users_total = _safe_int(ai_prompt_totals.get("users"))
        ai_tokens_total = _safe_int(ai_response_totals.get("tokens_total"))
        ai_estimated_cost_usd = round(_safe_float(ai_response_totals.get("estimated_cost_usd")), 6)

        prompt_rows = (
            results["ai_prompt_usage_by_user_type"]
            if isinstance(results["ai_prompt_usage_by_user_type"], list)
            else []
        )
        response_rows = (
            results["ai_response_usage_by_user_type"]
            if isinstance(results["ai_response_usage_by_user_type"], list)
            else []
        )
        ai_by_user_type: Dict[str, Dict[str, Any]] = {}
        for row in prompt_rows:
            if not isinstance(row, dict):
                continue
            user_type = _safe_str(row.get("user_type")) or "unknown"
            payload_row = ai_by_user_type.setdefault(
                user_type,
                {
                    "user_type": user_type,
                    "prompts_total": 0,
                    "tokens_total": 0,
                    "estimated_cost_usd": 0.0,
                    "users": 0,
                },
            )
            payload_row["prompts_total"] = _safe_int(row.get("prompts_total"))
            payload_row["users"] = max(
                _safe_int(payload_row.get("users")),
                _safe_int(row.get("users")),
            )
        for row in response_rows:
            if not isinstance(row, dict):
                continue
            user_type = _safe_str(row.get("user_type")) or "unknown"
            payload_row = ai_by_user_type.setdefault(
                user_type,
                {
                    "user_type": user_type,
                    "prompts_total": 0,
                    "tokens_total": 0,
                    "estimated_cost_usd": 0.0,
                    "users": 0,
                },
            )
            payload_row["tokens_total"] = _safe_int(row.get("tokens_total"))
            payload_row["estimated_cost_usd"] = round(
                _safe_float(row.get("estimated_cost_usd")),
                6,
            )
            payload_row["users"] = max(
                _safe_int(payload_row.get("users")),
                _safe_int(row.get("users")),
            )

        ai_user_type_rows = sorted(
            ai_by_user_type.values(),
            key=lambda item: (
                _safe_int(item.get("prompts_total")),
                _safe_int(item.get("tokens_total")),
            ),
            reverse=True,
        )
        for row in ai_user_type_rows:
            users = _safe_int(row.get("users"))
            prompts_total = _safe_int(row.get("prompts_total"))
            tokens_total = _safe_int(row.get("tokens_total"))
            cost_total = _safe_float(row.get("estimated_cost_usd"))
            row["avg_prompts_per_user"] = round(
                (prompts_total / users) if users > 0 else 0.0,
                2,
            )
            row["avg_tokens_per_user"] = round(
                (tokens_total / users) if users > 0 else 0.0,
                2,
            )
            row["avg_cost_usd_per_user"] = round(
                (cost_total / users) if users > 0 else 0.0,
                6,
            )

        payload["ai_usage"] = {
            "totals": {
                "prompts_total": ai_prompts_total,
                "tokens_total": ai_tokens_total,
                "estimated_cost_usd": ai_estimated_cost_usd,
                "users": ai_users_total,
                "avg_prompts_per_user": round(
                    (ai_prompts_total / ai_users_total) if ai_users_total > 0 else 0.0,
                    2,
                ),
                "avg_tokens_per_user": round(
                    (ai_tokens_total / ai_users_total) if ai_users_total > 0 else 0.0,
                    2,
                ),
                "avg_cost_usd_per_user": round(
                    (ai_estimated_cost_usd / ai_users_total) if ai_users_total > 0 else 0.0,
                    6,
                ),
            },
            "by_user_type": ai_user_type_rows,
        }
        payload["updated_at"] = _utc_now_iso()
        self._set_cached(cache_key, payload)
        return copy.deepcopy(payload)

    def _build_headers(self) -> Dict[str, str]:
        if not config.POSTHOG_PROJECT_ID:
            raise ValueError("PostHog project is not configured.")
        api_key = load_posthog_personal_api_key()
        return {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def _run_tasks(self, tasks: Dict[str, Callable[[], Any]]) -> Dict[str, Any]:
        if not tasks:
            return {}
        with ThreadPoolExecutor(max_workers=min(max(len(tasks), 1), 8)) as executor:
            futures = {
                key: executor.submit(task)
                for key, task in tasks.items()
            }
            return {
                key: future.result()
                for key, future in futures.items()
            }

    def _normalize_tool_usage_range_key(self, value: str) -> str:
        normalized = _safe_str(value).lower()
        if normalized in _TOOL_USAGE_RANGE_OPTIONS:
            return normalized
        return "30d"

    def _prompt_tool_usage_query(self, tool_usage_range_key: str) -> str:
        _, where_clause = _TOOL_USAGE_RANGE_OPTIONS[tool_usage_range_key]
        conditions = ["event = 'ai_prompt_cycle_completed'"]
        if where_clause:
            conditions.append(where_clause)
        combined_where = " AND ".join(conditions)
        return (
            "SELECT "
            "coalesce(nullIf(properties.tool_name, ''), nullIf(properties.resolved_tool, ''), 'unknown') AS tool_name, "
            "count() AS count "
            "FROM events "
            f"WHERE {combined_where} "
            "GROUP BY tool_name "
            "ORDER BY count DESC "
            "LIMIT 8"
        )

    def _range_filter_clause(self, tool_usage_range_key: str) -> str:
        return _TOOL_USAGE_RANGE_OPTIONS[tool_usage_range_key][1]

    def _event_where_clause(
        self,
        *,
        event_name: str,
        tool_usage_range_key: str,
        extra_conditions: List[str] | None = None,
    ) -> str:
        conditions = [f"event = '{event_name}'"]
        range_clause = self._range_filter_clause(tool_usage_range_key)
        if range_clause:
            conditions.append(range_clause)
        if extra_conditions:
            conditions.extend(extra_conditions)
        return " AND ".join(conditions)

    def _export_usage_totals_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="export_completed",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=[
                "person_id IS NOT NULL",
                "coalesce(nullIf(properties.export_type, ''), 'unknown') IN ('wav', 'mp3')",
            ],
        )
        return (
            "SELECT "
            "count() AS exports_total, "
            "countIf(properties.export_type = 'wav') AS exports_wav, "
            "countIf(properties.export_type = 'mp3') AS exports_mp3, "
            "count(DISTINCT person_id) AS users "
            "FROM events "
            f"WHERE {where_clause}"
        )

    def _export_usage_by_user_type_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="export_completed",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=[
                "person_id IS NOT NULL",
                "coalesce(nullIf(properties.export_type, ''), 'unknown') IN ('wav', 'mp3')",
            ],
        )
        return (
            "SELECT "
            f"{_USER_TYPE_EXPR} AS user_type, "
            "count() AS exports_total, "
            "countIf(properties.export_type = 'wav') AS exports_wav, "
            "countIf(properties.export_type = 'mp3') AS exports_mp3, "
            "count(DISTINCT person_id) AS users "
            "FROM events "
            f"WHERE {where_clause} "
            "GROUP BY user_type "
            "ORDER BY exports_total DESC "
            "LIMIT 12"
        )

    def _ai_prompt_usage_totals_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="ai_prompt_submitted",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=["person_id IS NOT NULL"],
        )
        return (
            "SELECT "
            "count() AS prompts_total, "
            "count(DISTINCT person_id) AS users "
            "FROM events "
            f"WHERE {where_clause}"
        )

    def _ai_response_usage_totals_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="ai_response_completed",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=["person_id IS NOT NULL"],
        )
        return (
            "SELECT "
            "sum(toFloat(properties.tokens_total)) AS tokens_total, "
            "sum(toFloat(properties.estimated_cost_usd)) AS estimated_cost_usd "
            "FROM events "
            f"WHERE {where_clause}"
        )

    def _ai_prompt_usage_by_user_type_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="ai_prompt_submitted",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=["person_id IS NOT NULL"],
        )
        return (
            "SELECT "
            f"{_USER_TYPE_EXPR} AS user_type, "
            "count() AS prompts_total, "
            "count(DISTINCT person_id) AS users "
            "FROM events "
            f"WHERE {where_clause} "
            "GROUP BY user_type "
            "ORDER BY prompts_total DESC "
            "LIMIT 12"
        )

    def _ai_response_usage_by_user_type_query(self, tool_usage_range_key: str) -> str:
        where_clause = self._event_where_clause(
            event_name="ai_response_completed",
            tool_usage_range_key=tool_usage_range_key,
            extra_conditions=["person_id IS NOT NULL"],
        )
        return (
            "SELECT "
            f"{_USER_TYPE_EXPR} AS user_type, "
            "sum(toFloat(properties.tokens_total)) AS tokens_total, "
            "sum(toFloat(properties.estimated_cost_usd)) AS estimated_cost_usd, "
            "count(DISTINCT person_id) AS users "
            "FROM events "
            f"WHERE {where_clause} "
            "GROUP BY user_type "
            "ORDER BY tokens_total DESC "
            "LIMIT 12"
        )

    def _post_query(
        self,
        headers: Dict[str, str],
        query: str,
        *,
        timeout_seconds: int | None = None,
    ) -> Dict[str, Any]:
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
                timeout=timeout_seconds or config.HTTP_TIMEOUT_SECONDS,
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

    def _query_rows(
        self,
        headers: Dict[str, str],
        query: str,
        *,
        timeout_seconds: int | None = None,
    ) -> List[Dict[str, Any]]:
        payload = self._post_query(headers, query, timeout_seconds=timeout_seconds)
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

    def _query_percentiles(
        self,
        headers: Dict[str, str],
        *,
        event_name: str,
        property_name: str,
    ) -> Dict[str, float]:
        rows = self._query_rows(
            headers,
            (
                "SELECT "
                f"round(quantile(0.5)(toFloat(properties.{property_name})), 2) AS p50, "
                f"round(quantile(0.95)(toFloat(properties.{property_name})), 2) AS p95 "
                "FROM events "
                f"WHERE event = '{event_name}' "
                f"AND timestamp >= now() - INTERVAL {_AI_OBSERVABILITY_RANGE_DAYS} DAY "
                f"AND properties.{property_name} IS NOT NULL"
            ),
        )
        if not rows:
            return {"p50": 0.0, "p95": 0.0}
        first = rows[0]
        return {
            "p50": _safe_float(first.get("p50")),
            "p95": _safe_float(first.get("p95")),
        }

    def _base_payload(
        self,
        *,
        status: str,
        note: str = "",
        tool_usage_range_key: str = "30d",
    ) -> Dict[str, Any]:
        range_key = self._normalize_tool_usage_range_key(tool_usage_range_key)
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
            "ai_observability": {
                key: value
                for key, value in self._base_ai_observability_payload(
                    status=status,
                    tool_usage_range_key=range_key,
                ).items()
                if key not in {"source", "status", "note", "updated_at"}
            },
        }
        if note:
            payload["note"] = note
        return payload

    def _base_ai_observability_payload(
        self,
        *,
        status: str,
        note: str = "",
        tool_usage_range_key: str = "30d",
    ) -> Dict[str, Any]:
        range_key = self._normalize_tool_usage_range_key(tool_usage_range_key)
        range_label = _TOOL_USAGE_RANGE_OPTIONS[range_key][0]
        payload = {
            "source": "posthog",
            "status": status,
            "updated_at": "",
            "range_days": _AI_OBSERVABILITY_RANGE_DAYS,
            "timings": {
                "prompt_cycle_total_ms": {"p50": 0.0, "p95": 0.0},
                "project_stats_ms": {"p50": 0.0, "p95": 0.0},
                "proxy_roundtrip_ms": {"p50": 0.0, "p95": 0.0},
                "openai_api_ms": {"p50": 0.0, "p95": 0.0},
                "mix_model_onnx_ms": {"p50": 0.0, "p95": 0.0},
            },
            "runtime_success": [],
            "magnitude_model_usage": [],
            "magnitude_model_updates": [],
            "prompt_tool_usage": [],
            "prompt_tool_usage_range": {
                "key": range_key,
                "label": range_label,
            },
            "export_usage": {
                "totals": {
                    "exports_total": 0,
                    "exports_wav": 0,
                    "exports_mp3": 0,
                    "users": 0,
                    "avg_exports_per_user": 0.0,
                },
                "by_user_type": [],
            },
            "ai_usage": {
                "totals": {
                    "prompts_total": 0,
                    "tokens_total": 0,
                    "estimated_cost_usd": 0.0,
                    "users": 0,
                    "avg_prompts_per_user": 0.0,
                    "avg_tokens_per_user": 0.0,
                    "avg_cost_usd_per_user": 0.0,
                },
                "by_user_type": [],
            },
        }
        if note:
            payload["note"] = note
        return payload

    def _cache_ttl_seconds(self) -> int:
        return max(60, config.POSTHOG_METRICS_CACHE_TTL_SECONDS)

    def _get_cached(self, cache_key: str) -> Dict[str, Any] | None:
        cached = self._cache.get(cache_key)
        now = time.time()
        if cached and now - cached[0] < self._cache_ttl_seconds():
            return copy.deepcopy(cached[1])
        return None

    def _set_cached(self, cache_key: str, payload: Dict[str, Any]) -> None:
        self._cache[cache_key] = (time.time(), copy.deepcopy(payload))
