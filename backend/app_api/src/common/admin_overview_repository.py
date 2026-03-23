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
    STATUSES,
    normalize_provider,
    normalize_status,
    normalize_tier,
    status_has_active_access,
)
from .repository import BillingRepository


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _safe_str(value: Any) -> str:
    return str(value or "").strip()


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


class AdminOverviewRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._ddb_client = boto3.client("dynamodb") if boto3 is not None else None
        self._entitlements = None
        self._ai_usage_state = None
        self._ai_usage_events = None
        self._billing_repo = BillingRepository() if boto3 is not None else None

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
    ) -> Dict[str, Any]:
        warnings: list[str] = []
        recent_app_profiles = self._recent_user_profiles(user_limit, warnings)
        user_records: dict[str, Dict[str, Any]] = {}
        tracked_user_ids: set[str] = set()

        total_credits_used_today = 0
        total_tokens_used_month = 0
        total_tokens_all_time = 0
        total_credits_all_time = 0
        request_total = 0
        success_count = 0
        failed_count = 0
        rate_limited_count = 0
        feature_counts: Counter[str] = Counter()
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
                record["subscription_tier"] = normalize_tier(_safe_str(entitlement.get("tier")))
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

        state_items = self._scan_state_items(warnings)
        for item in state_items:
            total_credits_used_today += _safe_int(item.get("ai_credits_used_today"))
            total_tokens_used_month += _safe_int(item.get("ai_tokens_used_month"))

        event_items = self._list_recent_ai_events(warnings)
        for item in event_items:
            request_total += 1
            status = _safe_str(item.get("status")).lower()
            if status == "success":
                success_count += 1
            elif status == "rate_limited":
                rate_limited_count += 1
            else:
                failed_count += 1

            feature = _safe_str(item.get("feature")) or "unknown"
            created_at = _safe_str(item.get("created_at"))
            credits_charged = _safe_int(item.get("credits_charged"))
            total_tokens = _safe_int(item.get("total_tokens"))

            feature_counts[feature] += 1
            total_credits_all_time += credits_charged
            total_tokens_all_time += total_tokens

            user_id = _safe_str(item.get("user_id"))
            if user_id and user_id in user_records:
                record = user_records[user_id]
                record["ai_request_count"] += 1
                record["ai_credits_charged_total"] += credits_charged
                record["ai_tokens_total"] += total_tokens
                record["last_ai_activity_at"] = _later_iso(
                    record["last_ai_activity_at"],
                    created_at,
                )
                record["last_seen_at"] = _later_iso(record["last_seen_at"], created_at)

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
        paid_users = sum(
            payload.get("active_user_count", 0)
            for payload in tier_breakdown
            if payload.get("tier") in ("pro", "studio")
        )
        active_subscriptions = sum(
            payload.get("active_user_count", 0)
            for payload in tier_breakdown
        ) - next(
            (payload.get("active_user_count", 0) for payload in tier_breakdown if payload.get("tier") == "free"),
            0,
        )

        users = sorted(
            (self._finalize_user_record(record) for record in user_records.values()),
            key=lambda item: (
                _parse_iso(item.get("last_seen_at")).timestamp()
                if _parse_iso(item.get("last_seen_at")) is not None
                else 0.0,
                item.get("display_name") or item.get("email") or item.get("user_id") or "",
            ),
            reverse=True,
        )[: max(user_limit, 1)]

        projects = sorted(
            (self._finalize_project_record(item) for item in project_records.values()),
            key=lambda item: (
                int(item.get("request_count") or 0),
                _parse_iso(item.get("last_activity_at")).timestamp()
                if _parse_iso(item.get("last_activity_at")) is not None
                else 0.0,
            ),
            reverse=True,
        )[: max(project_limit, 1)]

        top_features = [
            {
                "feature": feature,
                "request_count": count,
            }
            for feature, count in feature_counts.most_common(max(feature_limit, 1))
        ]

        return {
            "generated_at": _utc_now_iso(),
            "data_sources": {
                "entitlements": self._entitlements is not None,
                "ai_usage_state": self._ai_usage_state is not None,
                "ai_usage_events": self._ai_usage_events is not None,
            },
            "warnings": warnings,
            "summary": {
                "total_users": self._describe_item_count(config.USERS_TABLE, warnings),
                "tracked_users": self._describe_item_count(config.AI_USAGE_STATE_TABLE, warnings),
                "paid_users": paid_users,
                "active_subscriptions": active_subscriptions,
                "tracked_projects": len(project_records),
                "ai_requests_total": request_total,
                "ai_credits_used_today": total_credits_used_today,
                "ai_tokens_used_month": total_tokens_used_month,
                "ai_credits_charged_total": total_credits_all_time,
                "ai_tokens_total": total_tokens_all_time,
            },
            "subscription_tiers": tier_breakdown,
            "users": users,
            "projects": projects,
            "ai_usage": {
                "tracked_users": sum(
                    1 for item in state_items if _safe_str(item.get("user_id"))
                ),
                "event_records": request_total,
                "successful_requests": success_count,
                "failed_requests": failed_count,
                "rate_limited_requests": rate_limited_count,
                "top_features": top_features,
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
            "free": {"user_count": 0, "active_user_count": 0},
            "pro": {"user_count": 0, "active_user_count": 0},
            "studio": {"user_count": 0, "active_user_count": 0},
        }
        for user_id in tracked_user_ids:
            record = user_records.get(user_id) or {}
            tier = normalize_tier(record.get("subscription_tier") or "free")
            status = record.get("subscription_status") or ""
            counts[tier]["user_count"] += 1
            if status_has_active_access(status):
                counts[tier]["active_user_count"] += 1
        return [
            {
                "tier": tier,
                **payload,
            }
            for tier, payload in counts.items()
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
                    "ProjectionExpression": "tier, #status",
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(f"entitlement_scan_unavailable:{exc.__class__.__name__}")
                return total
            for item in response.get("Items", []):
                item_tier = normalize_tier(_safe_str(item.get("tier") or "free"))
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
                {"tier": "free", "user_count": 0, "active_user_count": 0},
                {"tier": "pro", "user_count": 0, "active_user_count": 0},
                {"tier": "studio", "user_count": 0, "active_user_count": 0},
            ]

        counts = {
            "free": {"user_count": 0, "active_user_count": 0},
            "pro": {"user_count": 0, "active_user_count": 0},
            "studio": {"user_count": 0, "active_user_count": 0},
        }
        start_key = None
        while True:
            try:
                kwargs = {
                    "ProjectionExpression": "tier, #status",
                    "ExpressionAttributeNames": {"#status": "status"},
                }
                if start_key:
                    kwargs["ExclusiveStartKey"] = start_key
                response = self._entitlements.scan(**kwargs)
            except (BotoCoreError, ClientError) as exc:
                warnings.append(f"entitlement_scan_unavailable:{exc.__class__.__name__}")
                return [
                    {"tier": tier, **payload}
                    for tier, payload in counts.items()
                ]

            for item in response.get("Items", []):
                tier = normalize_tier(_safe_str(item.get("tier") or "free"))
                status = normalize_status(_safe_str(item.get("status") or ""))
                counts[tier]["user_count"] += 1
                if status_has_active_access(status):
                    counts[tier]["active_user_count"] += 1

            start_key = response.get("LastEvaluatedKey")
            if not start_key:
                break

        return [
            {"tier": tier, **payload}
            for tier, payload in counts.items()
        ]

    def _build_tier_breakdown_fast(self, warnings: list[str]) -> list[Dict[str, Any]]:
        tiers = ("free", "pro", "studio")
        indexed_breakdown = [
            {
                "tier": tier,
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
