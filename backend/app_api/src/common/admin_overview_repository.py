from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

try:
    from boto3.dynamodb.conditions import Key
except (ImportError, ModuleNotFoundError):  # pragma: no cover - local dev/test fallback
    Key = None

try:
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        pass

    class BotoCoreError(Exception):
        pass

from . import config
from .models import (
    ACTIVE_ACCESS_STATUSES,
    PLAN_CODES,
    STATUSES,
    normalize_plan_code,
    normalize_provider,
    normalize_status,
    status_has_active_access,
)
from .posthog_admin_metrics import PosthogAdminMetricsClient
from .repository import BillingRepository


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


def _quantile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = max(0.0, min(percentile, 1.0)) * (len(ordered) - 1)
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    weight = rank - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def _parse_iso(value: Any) -> datetime | None:
    raw = _safe_str(value)
    if not raw:
        return None
    try:
        normalized = raw.replace("Z", "+00:00") if raw.endswith("Z") else raw
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def _datetime_to_iso(value: Any) -> str:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    return _safe_str(value)


def _later_iso(current: str, candidate: str) -> str:
    current_dt = _parse_iso(current)
    candidate_dt = _parse_iso(candidate)
    if candidate_dt is None:
        return current
    if current_dt is None or candidate_dt > current_dt:
        return candidate
    return current


def _tool_usage_range_label(value: str) -> str:
    normalized = _safe_str(value).lower()
    if normalized == "7d":
        return "Weekly"
    if normalized == "all":
        return "All time"
    return "Monthly"


class AdminOverviewRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._ddb_client = boto3.client("dynamodb") if boto3 is not None else None
        self._entitlements = None
        self._ai_usage_state = None
        self._ai_usage_events = None
        self._billing_repo = BillingRepository() if boto3 is not None else None
        self._posthog_metrics = PosthogAdminMetricsClient()

        if self._ddb is not None and config.ENTITLEMENTS_TABLE:
            self._entitlements = self._ddb.Table(config.ENTITLEMENTS_TABLE)
        if self._ddb is not None and config.AI_USAGE_STATE_TABLE:
            self._ai_usage_state = self._ddb.Table(config.AI_USAGE_STATE_TABLE)
        if self._ddb is not None and config.AI_USAGE_EVENTS_TABLE:
            self._ai_usage_events = self._ddb.Table(config.AI_USAGE_EVENTS_TABLE)

    def build_overview(
        self,
        *,
        user_limit: int = 24,
        project_limit: int = 24,
        feature_limit: int = 6,
        trace_limit: int = 6,
        include_ai_usage: bool = True,
        include_product_analytics: bool = True,
        include_ai_observability: bool = True,
        include_users: bool = True,
        include_projects: bool = True,
        tool_usage_range: str = "30d",
    ) -> Dict[str, Any]:
        warnings: list[str] = []
        now = datetime.now(timezone.utc)
        day_cutoff = now - timedelta(days=1)
        week_cutoff = now - timedelta(days=7)
        recent_app_profiles = (
            self._recent_user_profiles(user_limit, warnings) if include_users else []
        )
        user_records: dict[str, Dict[str, Any]] = {}
        tracked_user_ids: set[str] = set()

        request_total = 0
        success_count = 0
        failed_count = 0
        rate_limited_count = 0
        prompt_count_today = 0
        prompt_count_week = 0
        ai_active_users_today: set[str] = set()
        ai_active_users_week: set[str] = set()
        latency_total_today = 0.0
        latency_total_week = 0.0
        latency_count_today = 0
        latency_count_week = 0
        weekly_success_count = 0
        weekly_failed_count = 0
        weekly_rate_limited_count = 0
        weekly_feature_counts: Counter[str] = Counter()
        project_records: dict[str, Dict[str, Any]] = {}
        for profile in recent_app_profiles:
            user_id = _safe_str(profile.get("user_id"))
            if not user_id:
                continue
            tracked_user_ids.add(user_id)
            record = self._base_user_record(user_id, profile)
            entitlement = self._get_item(self._entitlements, user_id)
            state = self._get_item(self._ai_usage_state, user_id)
            if entitlement:
                updated_at = _safe_str(entitlement.get("updated_at") or entitlement.get("effective_at"))
                record["subscription_tier"] = normalize_plan_code(_safe_str(entitlement.get("plan_code")))
                record["subscription_status"] = normalize_status(_safe_str(entitlement.get("status")))
                record["subscription_provider"] = normalize_provider(
                    _safe_str(entitlement.get("source_provider"))
                )
                record["updated_at"] = updated_at
                record["last_seen_at"] = _later_iso(record["last_seen_at"], updated_at)
            if state:
                record["ai_credits_used_today"] = _safe_int(state.get("ai_credits_used_today"))
                record["ai_tokens_used_month"] = _safe_int(state.get("ai_tokens_used_month"))
                record["ai_last_reset"] = _safe_str(state.get("ai_last_reset"))
                record["ai_tokens_month_reset"] = _safe_str(state.get("ai_tokens_month_reset"))
                usage_updated_at = _safe_str(state.get("updated_at"))
                record["last_seen_at"] = _later_iso(record["last_seen_at"], usage_updated_at)
            user_records[user_id] = record

        should_load_event_items = include_ai_usage or include_projects or include_ai_observability
        event_items = self._list_recent_ai_events(warnings) if should_load_event_items else []
        for item in event_items:
            status = _safe_str(item.get("status")).lower()

            created_at = _safe_str(item.get("created_at"))
            created_at_dt = _parse_iso(created_at)
            credits_charged = _safe_int(item.get("credits_charged"))
            total_tokens = _safe_int(item.get("total_tokens"))
            user_id = _safe_str(item.get("user_id"))
            prompt_latency_ms = _safe_float(item.get("proxy_handler_ms_total"))

            if include_ai_usage:
                request_total += 1
                if status == "success":
                    success_count += 1
                elif status == "rate_limited":
                    rate_limited_count += 1
                else:
                    failed_count += 1

                feature = _safe_str(item.get("feature")) or "unknown"
                if created_at_dt is not None and created_at_dt >= week_cutoff:
                    prompt_count_week += 1
                    weekly_feature_counts[feature] += 1
                    if status == "success":
                        weekly_success_count += 1
                    elif status == "rate_limited":
                        weekly_rate_limited_count += 1
                    else:
                        weekly_failed_count += 1
                    if user_id:
                        ai_active_users_week.add(user_id)
                    if prompt_latency_ms > 0:
                        latency_total_week += prompt_latency_ms
                        latency_count_week += 1
                if created_at_dt is not None and created_at_dt >= day_cutoff:
                    prompt_count_today += 1
                    if user_id:
                        ai_active_users_today.add(user_id)
                    if prompt_latency_ms > 0:
                        latency_total_today += prompt_latency_ms
                        latency_count_today += 1

                if user_id and user_id in user_records:
                    record = user_records[user_id]
                    record["ai_request_count"] += 1
                    record["ai_tokens_total"] += total_tokens
                    record["last_ai_activity_at"] = _later_iso(
                        record["last_ai_activity_at"],
                        created_at,
                    )
                    record["last_seen_at"] = _later_iso(record["last_seen_at"], created_at)

            if include_projects:
                user_id = _safe_str(item.get("user_id"))
                project_id = _safe_str(item.get("project_id"))
                if not project_id:
                    continue
                project = project_records.setdefault(
                    project_id,
                    {
                        "project_id": project_id,
                        "request_count": 0,
                        "successful_request_count": 0,
                        "failed_request_count": 0,
                        "rate_limited_count": 0,
                        "credits_charged_total": 0,
                        "tokens_total": 0,
                        "last_activity_at": "",
                        "last_user_id": "",
                        "unique_user_count": 0,
                        "_users": set(),
                    },
                )
                project["request_count"] += 1
                project["successful_request_count"] += 1 if status == "success" else 0
                project["failed_request_count"] += 1 if status not in ("success", "rate_limited") else 0
                project["rate_limited_count"] += 1 if status == "rate_limited" else 0
                project["credits_charged_total"] += credits_charged
                project["tokens_total"] += total_tokens
                previous_activity = project["last_activity_at"]
                project["last_activity_at"] = _later_iso(previous_activity, created_at)
                if project["last_activity_at"] != previous_activity and user_id:
                    project["last_user_id"] = user_id
                if user_id:
                    users = project["_users"]
                    users.add(user_id)
                    project["unique_user_count"] = len(users)

        tier_breakdown = self._build_tier_breakdown_fast(warnings)
        paid_access = self._build_paid_access_breakdown(warnings)
        total_users = self._describe_item_count(config.USERS_TABLE, warnings)
        paid_users = paid_access.get("paid_users")
        paid_conversion_rate = (
            round((_safe_int(paid_users) / total_users) * 100, 1)
            if paid_users is not None and total_users > 0
            else 0.0 if paid_users is not None else None
        )

        users = (
            sorted(
                (self._finalize_user_record(record) for record in user_records.values()),
                key=lambda item: (
                    _parse_iso(item.get("last_seen_at")).timestamp()
                    if _parse_iso(item.get("last_seen_at")) is not None
                    else 0.0,
                    item.get("display_name") or item.get("email") or item.get("user_id") or "",
                ),
                reverse=True,
            )[: max(user_limit, 1)]
            if include_users
            else []
        )

        projects = (
            sorted(
                (self._finalize_project_record(item) for item in project_records.values()),
                key=lambda item: (
                    int(item.get("request_count") or 0),
                    _parse_iso(item.get("last_activity_at")).timestamp()
                    if _parse_iso(item.get("last_activity_at")) is not None
                    else 0.0,
                ),
                reverse=True,
            )[: max(project_limit, 1)]
            if include_projects
            else []
        )

        top_features = (
            [
                {
                    "feature": feature,
                    "request_count": count,
                }
                for feature, count in weekly_feature_counts.most_common(max(feature_limit, 1))
            ]
            if include_ai_usage
            else []
        )
        weekly_success_rate = (
            round((weekly_success_count / prompt_count_week) * 100, 1)
            if include_ai_usage and prompt_count_week > 0
            else None
        )
        avg_prompts_per_user_today = (
            round(prompt_count_today / len(ai_active_users_today), 1)
            if include_ai_usage and ai_active_users_today
            else None
        )
        avg_prompts_per_user_week = (
            round(prompt_count_week / len(ai_active_users_week), 1)
            if include_ai_usage and ai_active_users_week
            else None
        )
        avg_latency_ms_today = (
            round(latency_total_today / latency_count_today, 1)
            if include_ai_usage and latency_count_today > 0
            else None
        )
        avg_latency_ms_week = (
            round(latency_total_week / latency_count_week, 1)
            if include_ai_usage and latency_count_week > 0
            else None
        )
        product_analytics = self._deferred_product_analytics(tool_usage_range)
        if include_product_analytics:
            product_analytics = self._build_product_analytics(
                warnings,
                tool_usage_range=tool_usage_range,
            )
        posthog_ai_observability = None
        if include_ai_observability:
            posthog_ai_observability = self._build_posthog_ai_observability(
                warnings,
                tool_usage_range=tool_usage_range,
            )
        ai_observability = (
            self._build_ai_observability(
                event_items,
                posthog_ai_observability,
                recent_trace_limit=max(1, trace_limit),
            )
            if include_ai_observability
            else self._deferred_ai_observability(
                trace_limit,
                tool_usage_range=tool_usage_range,
            )
        )

        return {
            "generated_at": _utc_now_iso(),
            "section_includes": {
                "ai_usage": include_ai_usage,
                "product_analytics": include_product_analytics,
                "ai_observability": include_ai_observability,
                "users": include_users,
                "projects": include_projects,
            },
            "data_sources": {
                "entitlements": self._entitlements is not None,
                "ai_usage_state": self._ai_usage_state is not None,
                "ai_usage_events": self._ai_usage_events is not None,
            },
            "warnings": warnings,
            "summary": {
                "total_users": total_users,
                "tracked_users": self._describe_item_count(config.AI_USAGE_STATE_TABLE, warnings),
                "paid_users": paid_users,
                "active_subscriptions": paid_users,
                "paid_conversion_rate": paid_conversion_rate,
                "granted_premium_users": paid_access.get("granted_premium_users"),
                "premium_users": paid_access.get("premium_users"),
                "trial_users": paid_access.get("trial_users"),
                "unattributed_premium_users": paid_access.get(
                    "unattributed_premium_users"
                ),
                "ai_prompts_today": prompt_count_today if include_ai_usage else None,
                "ai_prompts_week": prompt_count_week if include_ai_usage else None,
                "ai_active_users_today": (
                    len(ai_active_users_today) if include_ai_usage else None
                ),
                "ai_active_users_week": (
                    len(ai_active_users_week) if include_ai_usage else None
                ),
                "avg_prompts_per_user_today": avg_prompts_per_user_today,
                "avg_prompts_per_user_week": avg_prompts_per_user_week,
                "avg_latency_ms_today": avg_latency_ms_today,
                "avg_latency_ms_week": avg_latency_ms_week,
                "ai_success_rate_week": weekly_success_rate,
                "tracked_projects": len(project_records) if include_projects else None,
            },
            "subscription_tiers": tier_breakdown,
            "users": users,
            "projects": projects,
            "ai_usage": (
                {
                    "tracked_users": self._describe_item_count(
                        config.AI_USAGE_STATE_TABLE,
                        warnings,
                    ),
                    "event_records": request_total,
                    "successful_requests": success_count,
                    "failed_requests": failed_count,
                    "rate_limited_requests": rate_limited_count,
                    "daily_request_count": prompt_count_today,
                    "weekly_request_count": prompt_count_week,
                    "active_users_today": len(ai_active_users_today),
                    "active_users_week": len(ai_active_users_week),
                    "avg_prompts_per_user_today": avg_prompts_per_user_today,
                    "avg_prompts_per_user_week": avg_prompts_per_user_week,
                    "avg_latency_ms_today": avg_latency_ms_today,
                    "avg_latency_ms_week": avg_latency_ms_week,
                    "success_rate_week": weekly_success_rate,
                    "top_features": top_features,
                }
                if include_ai_usage
                else self._deferred_ai_usage()
            ),
            "ai_observability": ai_observability,
            "product_analytics": product_analytics,
        }

    def build_live_presence(self) -> Dict[str, Any]:
        client = getattr(self, "_posthog_metrics", None)
        if client is None:
            return {
                "source": "posthog",
                "status": "unconfigured",
                "active_users": 0,
                "window_minutes": 5,
                "updated_at": "",
            }
        try:
            if hasattr(client, "fetch_live_presence"):
                return client.fetch_live_presence()
        except Exception:
            return {
                "source": "posthog",
                "status": "error",
                "active_users": 0,
                "window_minutes": 5,
                "updated_at": "",
            }
        return {
            "source": "posthog",
            "status": "unavailable",
            "active_users": 0,
            "window_minutes": 5,
            "updated_at": "",
        }

    def _deferred_ai_usage(self) -> Dict[str, Any]:
        return {
            "status": "deferred",
            "tracked_users": None,
            "event_records": None,
            "successful_requests": None,
            "failed_requests": None,
            "rate_limited_requests": None,
            "daily_request_count": None,
            "weekly_request_count": None,
            "active_users_today": None,
            "active_users_week": None,
            "avg_prompts_per_user_today": None,
            "avg_prompts_per_user_week": None,
            "avg_latency_ms_today": None,
            "avg_latency_ms_week": None,
            "success_rate_week": None,
            "top_features": [],
        }

    def _deferred_product_analytics(self, tool_usage_range: str) -> Dict[str, Any]:
        return {
            "source": "posthog",
            "status": "deferred",
            "note": "Loads in the background to keep the homepage fast.",
            "updated_at": "",
            "metrics": {
                "dau": None,
                "wau": None,
                "mau": None,
                "hours_24h": None,
            },
            "daily_active_users": [],
            "daily_hours_used": [],
            "top_countries": [],
            "ai_observability": {
                "range_days": 30,
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
                    "key": _safe_str(tool_usage_range).lower() or "30d",
                    "label": _tool_usage_range_label(tool_usage_range),
                },
            },
        }

    def _deferred_ai_observability(
        self,
        trace_limit: int,
        *,
        tool_usage_range: str,
    ) -> Dict[str, Any]:
        return {
            "recent_traces": [],
            "recent_traces_meta": {
                "shown_count": 0,
                "total_count": None,
                "has_more": False,
                "limit": max(1, trace_limit),
                "included": False,
            },
            "dashboard_metrics": {
                "prompt_tool_usage_range": {
                    "key": _safe_str(tool_usage_range).lower() or "30d",
                    "label": _tool_usage_range_label(tool_usage_range),
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
            },
            "dashboard_status": "deferred",
            "dashboard_updated_at": "",
            "backend_timings": {
                "proxy_handler_ms_total": {"p50": 0.0, "p95": 0.0},
                "provider_roundtrip_ms": {"p50": 0.0, "p95": 0.0},
                "response_normalize_ms": {"p50": 0.0, "p95": 0.0},
            },
            "counts": {
                "runtime_config_fingerprint": [],
                "effective_model": [],
                "platform": [],
                "app_version": [],
            },
        }

    def _build_product_analytics(
        self,
        warnings: list[str],
        *,
        tool_usage_range: str = "30d",
    ) -> Dict[str, Any]:
        client = getattr(self, "_posthog_metrics", None)
        if client is None:
            return {
                "source": "posthog",
                "status": "unconfigured",
                "metrics": {
                    "dau": 0,
                    "wau": 0,
                    "mau": 0,
                    "hours_24h": 0.0,
                },
                "daily_active_users": [],
                "daily_hours_used": [],
                "top_countries": [],
                "updated_at": "",
            }
        try:
            if hasattr(client, "fetch_product_metrics"):
                return client.fetch_product_metrics(tool_usage_range_key=tool_usage_range)
            return client.fetch(tool_usage_range_key=tool_usage_range)
        except Exception as exc:
            warnings.append(f"posthog_metrics_unavailable:{exc.__class__.__name__}")
            return {
                "source": "posthog",
                "status": "error",
                "metrics": {
                    "dau": 0,
                    "wau": 0,
                    "mau": 0,
                    "hours_24h": 0.0,
                },
                "daily_active_users": [],
                "daily_hours_used": [],
                "top_countries": [],
                "updated_at": "",
            }

    def _build_posthog_ai_observability(
        self,
        warnings: list[str],
        *,
        tool_usage_range: str = "30d",
    ) -> Dict[str, Any]:
        client = getattr(self, "_posthog_metrics", None)
        deferred_dashboard = self._deferred_ai_observability(
            1,
            tool_usage_range=tool_usage_range,
        )["dashboard_metrics"]
        if client is None:
            return {
                "source": "posthog",
                "status": "unconfigured",
                "updated_at": "",
                **deferred_dashboard,
            }
        try:
            if hasattr(client, "fetch_ai_observability"):
                return client.fetch_ai_observability(tool_usage_range_key=tool_usage_range)
            product_analytics = client.fetch(tool_usage_range_key=tool_usage_range)
            nested = (
                product_analytics.get("ai_observability")
                if isinstance(product_analytics, dict)
                and isinstance(product_analytics.get("ai_observability"), dict)
                else {}
            )
            return {
                "source": "posthog",
                "status": _safe_str(product_analytics.get("status")),
                "updated_at": _safe_str(product_analytics.get("updated_at")),
                **nested,
            }
        except Exception as exc:
            warnings.append(f"posthog_observability_unavailable:{exc.__class__.__name__}")
            return {
                "source": "posthog",
                "status": "error",
                "updated_at": "",
                **deferred_dashboard,
            }

    def _build_ai_observability(
        self,
        event_items: list[Dict[str, Any]],
        posthog_ai_observability: Dict[str, Any] | None,
        *,
        recent_trace_limit: int = 6,
    ) -> Dict[str, Any]:
        prompt_cycle_values: list[float] = []
        provider_values: list[float] = []
        normalize_values: list[float] = []
        runtime_counts: Counter[str] = Counter()
        model_counts: Counter[str] = Counter()
        platform_counts: Counter[str] = Counter()
        app_version_counts: Counter[str] = Counter()
        recent_traces: list[Dict[str, Any]] = []
        recent_trace_total = 0

        for item in event_items:
            fingerprint = _safe_str(item.get("runtime_config_fingerprint")) or "unknown"
            model = _safe_str(item.get("model")) or _safe_str(item.get("effective_model")) or "unknown"
            platform = _safe_str(item.get("platform")) or "unknown"
            app_version = _safe_str(item.get("app_version")) or "unknown"

            runtime_counts[fingerprint] += 1
            model_counts[model] += 1
            platform_counts[platform] += 1
            app_version_counts[app_version] += 1

            proxy_handler_ms_total = _safe_float(item.get("proxy_handler_ms_total"))
            provider_roundtrip_ms = _safe_float(item.get("provider_roundtrip_ms"))
            response_normalize_ms = _safe_float(item.get("response_normalize_ms"))
            if proxy_handler_ms_total > 0:
                prompt_cycle_values.append(proxy_handler_ms_total)
            if provider_roundtrip_ms > 0:
                provider_values.append(provider_roundtrip_ms)
            if response_normalize_ms > 0:
                normalize_values.append(response_normalize_ms)

            recent_trace_total += 1
            if len(recent_traces) < recent_trace_limit:
                recent_traces.append(
                    {
                        "prompt_trace_id": _safe_str(item.get("prompt_trace_id")),
                        "request_id": _safe_str(item.get("request_id")),
                        "provider_response_id": _safe_str(item.get("provider_response_id")),
                        "runtime_config_fingerprint": fingerprint,
                        "effective_model": model,
                        "resolved_tool": _safe_str(item.get("resolved_tool")) or "unknown",
                        "status": _safe_str(item.get("status")) or "unknown",
                        "provider": _safe_str(item.get("provider")) or "unknown",
                        "platform": platform,
                        "app_version": app_version,
                        "project_id": _safe_str(item.get("project_id")),
                        "created_at": _safe_str(item.get("created_at")),
                        "proxy_handler_ms_total": _safe_int(item.get("proxy_handler_ms_total")),
                        "provider_roundtrip_ms": _safe_int(item.get("provider_roundtrip_ms")),
                        "response_normalize_ms": _safe_int(item.get("response_normalize_ms")),
                    }
                )

        dashboard = (
            {
                key: value
                for key, value in posthog_ai_observability.items()
                if key not in {"source", "status", "note", "updated_at"}
            }
            if isinstance(posthog_ai_observability, dict)
            else {}
        )
        return {
            "recent_traces": recent_traces,
            "recent_traces_meta": {
                "shown_count": len(recent_traces),
                "total_count": recent_trace_total,
                "has_more": recent_trace_total > len(recent_traces),
                "limit": recent_trace_limit,
            },
            "dashboard_metrics": dashboard,
            "dashboard_status": _safe_str((posthog_ai_observability or {}).get("status")),
            "dashboard_updated_at": _safe_str((posthog_ai_observability or {}).get("updated_at")),
            "backend_timings": {
                "proxy_handler_ms_total": {
                    "p50": round(_quantile(prompt_cycle_values, 0.5), 2),
                    "p95": round(_quantile(prompt_cycle_values, 0.95), 2),
                },
                "provider_roundtrip_ms": {
                    "p50": round(_quantile(provider_values, 0.5), 2),
                    "p95": round(_quantile(provider_values, 0.95), 2),
                },
                "response_normalize_ms": {
                    "p50": round(_quantile(normalize_values, 0.5), 2),
                    "p95": round(_quantile(normalize_values, 0.95), 2),
                },
            },
            "counts": {
                "runtime_config_fingerprint": [
                    {"value": key, "count": count}
                    for key, count in runtime_counts.most_common(8)
                ],
                "effective_model": [
                    {"value": key, "count": count}
                    for key, count in model_counts.most_common(8)
                ],
                "platform": [
                    {"value": key, "count": count}
                    for key, count in platform_counts.most_common(8)
                ],
                "app_version": [
                    {"value": key, "count": count}
                    for key, count in app_version_counts.most_common(8)
                ],
            },
        }

    def _base_user_record(
        self,
        user_id: str,
        profile: Dict[str, Any] | None = None,
    ) -> Dict[str, Any]:
        profile = profile or {}
        created_at = _safe_str(profile.get("created_at"))
        updated_at = _safe_str(profile.get("updated_at"))
        last_seen_at = updated_at or created_at
        return {
            "user_id": user_id,
            "email": _safe_str(profile.get("email")),
            "display_name": _safe_str(profile.get("display_name")),
            "auth_status": _safe_str(profile.get("auth_status")),
            "account_enabled": bool(profile.get("account_enabled", False)),
            "created_at": created_at,
            "updated_at": "",
            "subscription_tier": "",
            "subscription_status": "",
            "subscription_provider": "",
            "ai_request_count": 0,
            "ai_credits_used_today": 0,
            "ai_tokens_used_month": 0,
            "ai_credits_charged_total": 0,
            "ai_tokens_total": 0,
            "ai_last_reset": "",
            "ai_tokens_month_reset": "",
            "last_ai_activity_at": "",
            "last_seen_at": last_seen_at,
        }

    def _build_tier_breakdown(
        self,
        user_records: Dict[str, Dict[str, Any]],
        tracked_user_ids: set[str],
    ) -> list[Dict[str, Any]]:
        counts: dict[str, Dict[str, int]] = {
            plan_code: {"user_count": 0, "active_user_count": 0}
            for plan_code in PLAN_CODES
        }
        for user_id in tracked_user_ids:
            record = user_records.get(user_id) or {}
            plan_code = normalize_plan_code(record.get("subscription_tier") or "free")
            status = record.get("subscription_status") or ""
            counts.setdefault(plan_code, {"user_count": 0, "active_user_count": 0})
            counts[plan_code]["user_count"] += 1
            if status_has_active_access(status):
                counts[plan_code]["active_user_count"] += 1
        return [
            {
                "plan_code": plan_code,
                **payload,
            }
            for plan_code, payload in counts.items()
        ]

    def _finalize_project_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        return {
            key: value
            for key, value in record.items()
            if not key.startswith("_")
        }

    def _finalize_user_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        return dict(record)

    def _recent_user_profiles(
        self,
        limit: int,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._billing_repo is None:
            return []
        try:
            return self._billing_repo.list_recent_user_profiles(limit=max(limit, 1))
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"users_table_unavailable:{exc.__class__.__name__}")
            return []

    def _scan_state_items(
        self,
        warnings: list[str],
    ) -> list[Dict[str, Any]]:
        if self._ai_usage_state is None:
            return []

        items: list[Dict[str, Any]] = []
        start_key = None
        while True:
            try:
                kwargs: dict[str, Any] = {
                    "ProjectionExpression": "user_id, ai_credits_used_today, ai_tokens_used_month",
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._ai_usage_state.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(f"ai_usage_state_unavailable:{exc.__class__.__name__}")
                return items

            items.extend(response.get("Items", []))
            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break
        return items

    def _list_recent_ai_events(self, warnings: list[str]) -> list[Dict[str, Any]]:
        if self._ai_usage_events is None:
            return []
        since = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
        items: list[Dict[str, Any]] = []
        start_key = None
        try:
            while True:
                kwargs: dict[str, Any] = {
                    "IndexName": "created_at_idx",
                    "KeyConditionExpression": Key("record_type").eq("ai_usage_event")
                    & Key("created_at").gte(since),
                    "ScanIndexForward": False,
                    "Limit": 500,
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._ai_usage_events.query(**kwargs)
                items.extend(response.get("Items", []))
                start_key = response.get("LastEvaluatedKey")
                if not start_key or len(items) >= 2000:
                    break
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"ai_usage_events_unavailable:{exc.__class__.__name__}")
            return []
        return [item for item in items if isinstance(item, dict)]

    def _describe_item_count(self, table_name: str, warnings: list[str]) -> int:
        safe_name = _safe_str(table_name)
        if not safe_name or self._ddb_client is None:
            return 0
        try:
            response = self._ddb_client.describe_table(TableName=safe_name)
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"table_count_unavailable:{safe_name}:{exc.__class__.__name__}")
            return 0
        return _safe_int((response.get("Table") or {}).get("ItemCount"))

    def _get_item(self, table: Any, user_id: str) -> Dict[str, Any]:
        if table is None or not user_id:
            return {}
        try:
            return table.get_item(Key={"user_id": user_id}).get("Item") or {}
        except (BotoCoreError, ClientError):
            return {}

    def _count_entitlements(
        self,
        *,
        tier: str | None = None,
        statuses: Iterable[str],
        warnings: list[str],
    ) -> int:
        if self._entitlements is None:
            return 0
        normalized_statuses = {str(status or "").strip().lower() for status in statuses if str(status or "").strip()}
        total = 0
        try:
            for status in normalized_statuses:
                kwargs: dict[str, Any]
                if tier:
                    kwargs = {
                        "IndexName": "tier_status_idx",
                        "KeyConditionExpression": Key("tier_key").eq(tier) & Key("status_key").eq(status),
                        "Select": "COUNT",
                    }
                else:
                    kwargs = {
                        "IndexName": "status_idx",
                        "KeyConditionExpression": Key("status_key").eq(status),
                        "Select": "COUNT",
                    }
                response = self._entitlements.query(**kwargs)
                total += _safe_int(response.get("Count"))
            return total
        except (BotoCoreError, ClientError) as exc:
            warnings.append(f"entitlement_count_unavailable:{exc.__class__.__name__}")

        start_key = None
        while True:
            try:
                kwargs = {
                    "ProjectionExpression": "plan_code, #status",
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(f"entitlement_scan_unavailable:{exc.__class__.__name__}")
                return total
            for item in response.get("Items", []):
                item_tier = normalize_plan_code(_safe_str(item.get("plan_code") or "free"))
                item_status = normalize_status(_safe_str(item.get("status") or ""))
                if tier and item_tier != tier:
                    continue
                if item_status in normalized_statuses:
                    total += 1
            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break
        return total

    def _scan_tier_breakdown(self, warnings: list[str]) -> list[Dict[str, Any]]:
        if self._entitlements is None:
            return [
                {"plan_code": plan_code, "user_count": 0, "active_user_count": 0}
                for plan_code in PLAN_CODES
            ]

        counts = {
            plan_code: {"user_count": 0, "active_user_count": 0}
            for plan_code in PLAN_CODES
        }
        start_key = None
        while True:
            try:
                kwargs = {
                    "ProjectionExpression": "plan_code, #status",
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(f"entitlement_scan_unavailable:{exc.__class__.__name__}")
                return [
                    {"plan_code": tier, **payload}
                    for tier, payload in counts.items()
                ]

            for item in response.get("Items", []):
                tier = normalize_plan_code(_safe_str(item.get("plan_code") or "free"))
                counts.setdefault(tier, {"user_count": 0, "active_user_count": 0})
                status = normalize_status(_safe_str(item.get("status") or ""))
                counts[tier]["user_count"] += 1
                if status_has_active_access(status):
                    counts[tier]["active_user_count"] += 1

            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break

        return [
            {"plan_code": tier, **payload}
            for tier, payload in counts.items()
        ]

    def _build_paid_access_breakdown(
        self,
        warnings: list[str],
    ) -> Dict[str, int | None]:
        """Count active paid-plan access by its authoritative entitlement source."""
        unavailable = {
            "paid_users": None,
            "granted_premium_users": None,
            "unattributed_premium_users": None,
            "trial_users": None,
            "premium_users": None,
        }
        if self._entitlements is None:
            return unavailable

        paid_users = 0
        granted_premium_users = 0
        unattributed_premium_users = 0
        trial_users = 0
        start_key = None
        while True:
            try:
                kwargs: dict[str, Any] = {
                    "ProjectionExpression": "plan_code, #status, source_provider",
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(
                    f"paid_access_breakdown_unavailable:{exc.__class__.__name__}"
                )
                return unavailable

            for item in response.get("Items", []):
                plan_code = normalize_plan_code(item.get("plan_code") or "free")
                status = normalize_status(_safe_str(item.get("status")))
                if plan_code == "free" or not status_has_active_access(status):
                    continue
                provider = normalize_provider(_safe_str(item.get("source_provider")))
                if provider == "admin_grant":
                    granted_premium_users += 1
                elif status == "trialing":
                    trial_users += 1
                elif provider == "unknown":
                    unattributed_premium_users += 1
                else:
                    paid_users += 1

            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break

        premium_users = (
            paid_users
            + granted_premium_users
            + unattributed_premium_users
            + trial_users
        )
        if unattributed_premium_users:
            warnings.append(
                f"premium_access_source_unknown:{unattributed_premium_users}"
            )
        return {
            "paid_users": paid_users,
            "granted_premium_users": granted_premium_users,
            "unattributed_premium_users": unattributed_premium_users,
            "trial_users": trial_users,
            "premium_users": premium_users,
        }

    def _build_tier_breakdown_fast(self, warnings: list[str]) -> list[Dict[str, Any]]:
        tiers = PLAN_CODES
        indexed_breakdown = [
            {
                "plan_code": tier,
                "user_count": self._count_entitlements(
                    tier=tier,
                    statuses=STATUSES,
                    warnings=warnings,
                ),
                "active_user_count": self._count_entitlements(
                    tier=tier,
                    statuses=ACTIVE_ACCESS_STATUSES,
                    warnings=warnings,
                ),
            }
            for tier in tiers
        ]
        if self._entitlements is None:
            return indexed_breakdown

        indexed_total = sum(
            _safe_int(payload.get("user_count"))
            for payload in indexed_breakdown
        )
        entitlement_item_count = self._describe_item_count(
            config.ENTITLEMENTS_TABLE,
            warnings,
        )
        if entitlement_item_count > 0 and indexed_total < entitlement_item_count:
            warnings.append(
                f"entitlement_index_stale:indexed={indexed_total}:table={entitlement_item_count}"
            )
            return self._scan_tier_breakdown(warnings)
        return indexed_breakdown
