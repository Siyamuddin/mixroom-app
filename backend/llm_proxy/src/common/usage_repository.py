from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import uuid4

try:
    from botocore.exceptions import ClientError
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    class ClientError(Exception):
        response: dict[str, Any]

from . import config
from .ai_limits import get_prompt_limits

try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover - local dev/test fallback
    boto3 = None

_ACTIVE_ENTITLEMENT_STATUSES = {"trialing", "active", "grace_period"}
_ORG_PLAN_CODES = {"starter", "producer", "studio", "enterprise", "education"}


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _utc_now_iso(now: datetime | None = None) -> str:
    return (now or _utc_now()).isoformat()


def _parse_datetime(raw: Any) -> datetime | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw.astimezone(timezone.utc)
    text = str(raw).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(
            timezone.utc
        )
    except Exception:
        return None


def _effective_entitlement_status(item: dict[str, Any]) -> str:
    status = str(item.get("status") or "active").strip().lower()
    expires_at = _parse_datetime(item.get("expires_at"))
    if (
        status in _ACTIVE_ENTITLEMENT_STATUSES
        and expires_at is not None
        and expires_at <= _utc_now()
    ):
        return "expired"
    return status


def _current_day_key(now: datetime | None = None) -> str:
    return (now or _utc_now()).date().isoformat()


def _current_month_key(now: datetime | None = None) -> str:
    current = now or _utc_now()
    return f"{current.year:04d}-{current.month:02d}"


def _current_week_key(now: datetime | None = None) -> str:
    current = now or _utc_now()
    week_start = datetime(
        current.year,
        current.month,
        current.day,
        tzinfo=current.tzinfo or timezone.utc,
    ) - timedelta(days=current.weekday())
    return week_start.date().isoformat()


def _next_day_reset_at(now: datetime | None = None) -> datetime:
    current = now or _utc_now()
    start_of_day = datetime(
        current.year,
        current.month,
        current.day,
        tzinfo=current.tzinfo or timezone.utc,
    )
    return start_of_day + timedelta(days=1)


def _next_week_reset_at(now: datetime | None = None) -> datetime:
    current = now or _utc_now()
    start_of_day = datetime(
        current.year,
        current.month,
        current.day,
        tzinfo=current.tzinfo or timezone.utc,
    )
    return start_of_day + timedelta(days=(7 - current.weekday()))


def _int_value(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _prompt_quota_remaining(used: int, limit: int) -> int:
    return max(max(int(limit or 0), 0) - max(int(used or 0), 0), 0)


def _reserved_prompt_split(
    *,
    reserved_prompts: int,
    bonus_remaining: int,
) -> tuple[int, int]:
    safe_reserved = max(int(reserved_prompts or 0), 0)
    safe_bonus = max(int(bonus_remaining or 0), 0)
    grant_prompts = min(safe_reserved, safe_bonus)
    quota_prompts = safe_reserved - grant_prompts
    return quota_prompts, grant_prompts


def _prompt_limit_failure_reason(
    *,
    daily_used: int,
    weekly_used: int,
    bonus_remaining: int,
    reserved_prompts: int,
    daily_prompt_limit: int,
    weekly_prompt_limit: int,
) -> str:
    quota_prompts, _grant_prompts = _reserved_prompt_split(
        reserved_prompts=reserved_prompts,
        bonus_remaining=bonus_remaining,
    )
    daily_remaining = _prompt_quota_remaining(daily_used, daily_prompt_limit)
    weekly_remaining = _prompt_quota_remaining(weekly_used, weekly_prompt_limit)
    if daily_remaining < quota_prompts:
        return "daily_prompts"
    if weekly_remaining < quota_prompts:
        return "weekly_prompts"
    return ""


@dataclass(frozen=True)
class UsageReservationResult:
    allowed: bool
    limit_reason: str = ""
    reserved_quota_prompts: int = 0
    reserved_grant_prompts: int = 0


class AiUsageRepository:
    def __init__(self) -> None:
        self._ddb = boto3.resource("dynamodb") if boto3 is not None else None
        self._state_table = None
        self._events_table = None
        self._entitlements_table = None
        self._collaboration_table = None
        if self._ddb is None:
            return
        if config.AI_USAGE_STATE_TABLE:
            self._state_table = self._ddb.Table(config.AI_USAGE_STATE_TABLE)
        if config.AI_USAGE_EVENTS_TABLE:
            self._events_table = self._ddb.Table(config.AI_USAGE_EVENTS_TABLE)
        if config.ENTITLEMENTS_TABLE:
            self._entitlements_table = self._ddb.Table(config.ENTITLEMENTS_TABLE)
        if config.COLLABORATION_TABLE:
            self._collaboration_table = self._ddb.Table(config.COLLABORATION_TABLE)

    def load_user_context(self, user_id: str) -> dict[str, Any]:
        if not user_id:
            return {}

        entitlement_context: dict[str, Any] | None = None
        if self._entitlements_table is not None:
            item = (
                self._entitlements_table.get_item(
                    Key={"user_id": user_id},
                    ConsistentRead=True,
                ).get("Item")
                or {}
            )
            status = _effective_entitlement_status(item)
            tier = str(
                item.get("plan_code") or item.get("tier") or "free"
            ).strip().lower()
            if status not in _ACTIVE_ENTITLEMENT_STATUSES:
                tier = "free"
            if tier:
                context = {
                    "user_id": user_id,
                    "subscription_tier": tier,
                    "tier": tier,
                    "entitlement_status": status,
                }
                if (
                    status in _ACTIVE_ENTITLEMENT_STATUSES
                    and isinstance(item.get("limits"), dict)
                ):
                    context["limits"] = item.get("limits") or {}
                entitlement_context = context

        organization_context = self._load_organization_entitlement_context(user_id)
        if entitlement_context and organization_context:
            return self._higher_prompt_limit_context(
                entitlement_context,
                organization_context,
            )
        if entitlement_context:
            return entitlement_context
        if organization_context:
            return organization_context

        item = self.get_usage_state(user_id)
        if not item:
            return {"user_id": user_id, "subscription_tier": "free", "tier": "free"}

        tier = str(item.get("subscription_tier") or "free").strip().lower() or "free"
        return {
            "user_id": user_id,
            "subscription_tier": tier,
            "tier": tier,
        }

    def _load_organization_entitlement_context(self, user_id: str) -> dict[str, Any]:
        if getattr(self, "_collaboration_table", None) is None:
            return {}
        try:
            memberships = (
                self._collaboration_table.query(
                    IndexName="user_updated_idx",
                    KeyConditionExpression="#user_id = :user_id",
                    ExpressionAttributeNames={"#user_id": "user_id"},
                    ExpressionAttributeValues={":user_id": user_id},
                ).get("Items")
                or []
            )
        except Exception:
            return {}

        best_context: dict[str, Any] = {}
        for membership in memberships:
            if str(membership.get("entity_type") or "") != "membership":
                continue
            if str(membership.get("status") or "").strip().lower() != "active":
                continue
            organization_id = str(membership.get("organization_id") or "").strip()
            if not organization_id:
                continue
            organization = self._load_organization(organization_id)
            if not organization:
                continue
            if str(organization.get("status") or "").strip().lower() != "active":
                continue
            plan_code = str(organization.get("plan_code") or "").strip().lower()
            if plan_code not in _ORG_PLAN_CODES:
                continue
            context = {
                "user_id": user_id,
                "subscription_tier": plan_code,
                "tier": plan_code,
                "entitlement_status": "active",
                "source_type": "organization",
                "organization_id": organization_id,
            }
            best_context = self._higher_prompt_limit_context(best_context, context)
        return best_context

    def _load_organization(self, organization_id: str) -> dict[str, Any]:
        if getattr(self, "_collaboration_table", None) is None:
            return {}
        try:
            return (
                self._collaboration_table.get_item(
                    Key={"entity_id": f"organization#{organization_id}"},
                    ConsistentRead=True,
                ).get("Item")
                or {}
            )
        except Exception:
            return {}

    def _higher_prompt_limit_context(
        self,
        current: dict[str, Any],
        candidate: dict[str, Any],
    ) -> dict[str, Any]:
        if not current:
            return candidate
        if not candidate:
            return current
        current_limits = get_prompt_limits(
            str(current.get("subscription_tier") or "free"),
            current.get("limits") if isinstance(current.get("limits"), dict) else None,
        )
        candidate_limits = get_prompt_limits(
            str(candidate.get("subscription_tier") or "free"),
            candidate.get("limits") if isinstance(candidate.get("limits"), dict) else None,
        )
        current_score = (
            int(current_limits.get("daily_prompts") or 0),
            int(current_limits.get("weekly_prompts") or 0),
        )
        candidate_score = (
            int(candidate_limits.get("daily_prompts") or 0),
            int(candidate_limits.get("weekly_prompts") or 0),
        )
        return candidate if candidate_score > current_score else current

    def ensure_usage_state(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        now: datetime | None = None,
    ) -> None:
        if self._state_table is None:
            raise RuntimeError("AI usage state table is not configured.")
        current = now or _utc_now()
        try:
            self._state_table.put_item(
                Item={
                    "user_id": user_id,
                    "ai_credits_used_today": 0,
                    "ai_tokens_used_month": 0,
                    "ai_prompts_used_today": 0,
                    "ai_prompts_used_week": 0,
                    "admin_prompt_grants_total": 0,
                    "admin_prompt_grants_remaining": 0,
                    "ai_last_reset": _current_day_key(current),
                    "ai_tokens_month_reset": _current_month_key(current),
                    "ai_prompts_day_reset": _current_day_key(current),
                    "ai_prompts_week_reset": _current_week_key(current),
                    "subscription_tier": subscription_tier,
                    "updated_at": _utc_now_iso(current),
                },
                ConditionExpression="attribute_not_exists(user_id)",
            )
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
                raise

    def reset_counters_if_needed(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        now: datetime | None = None,
    ) -> None:
        if self._state_table is None:
            raise RuntimeError("AI usage state table is not configured.")

        current = now or _utc_now()
        self.ensure_usage_state(user_id, subscription_tier=subscription_tier, now=current)
        self._conditional_update(
            Key={"user_id": user_id},
            UpdateExpression=(
                "SET ai_prompts_used_today = :zero, "
                "ai_prompts_day_reset = :today, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            ),
            ConditionExpression=(
                "attribute_exists(user_id) AND "
                "("
                "attribute_not_exists(ai_prompts_day_reset) OR "
                "ai_prompts_day_reset <> :today OR "
                "attribute_not_exists(ai_prompts_used_today)"
                ")"
            ),
            ExpressionAttributeValues={
                ":zero": 0,
                ":today": _current_day_key(current),
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            },
        )
        self._conditional_update(
            Key={"user_id": user_id},
            UpdateExpression=(
                "SET ai_prompts_used_week = :zero, "
                "ai_prompts_week_reset = :week, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            ),
            ConditionExpression=(
                "attribute_exists(user_id) AND "
                "("
                "attribute_not_exists(ai_prompts_week_reset) OR "
                "ai_prompts_week_reset <> :week OR "
                "attribute_not_exists(ai_prompts_used_week)"
                ")"
            ),
            ExpressionAttributeValues={
                ":zero": 0,
                ":week": _current_week_key(current),
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            },
        )
        self._conditional_update(
            Key={"user_id": user_id},
            UpdateExpression=(
                "SET ai_credits_used_today = :zero, "
                "ai_last_reset = :today, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            ),
            ConditionExpression=(
                "attribute_exists(user_id) AND "
                "(attribute_not_exists(ai_last_reset) OR ai_last_reset <> :today)"
            ),
            ExpressionAttributeValues={
                ":zero": 0,
                ":today": _current_day_key(current),
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            },
        )
        self._conditional_update(
            Key={"user_id": user_id},
            UpdateExpression=(
                "SET ai_tokens_used_month = :zero, "
                "ai_tokens_month_reset = :month, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            ),
            ConditionExpression=(
                "attribute_exists(user_id) AND "
                "(attribute_not_exists(ai_tokens_month_reset) OR ai_tokens_month_reset <> :month)"
            ),
            ExpressionAttributeValues={
                ":zero": 0,
                ":month": _current_month_key(current),
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            },
        )

    def get_usage_state(self, user_id: str) -> dict[str, Any]:
        if self._state_table is None or not user_id:
            return {}
        return (
            self._state_table.get_item(
                Key={"user_id": user_id},
                ConsistentRead=True,
            ).get("Item")
            or {}
        )

    def reserve_usage(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        reserved_credits: int,
        reserved_tokens: int,
        reserved_prompts: int = 0,
        daily_credit_limit: int,
        monthly_token_limit: int,
        daily_prompt_limit: int = 0,
        weekly_prompt_limit: int = 0,
        now: datetime | None = None,
    ) -> UsageReservationResult:
        if self._state_table is None:
            raise RuntimeError("AI usage state table is not configured.")

        current = now or _utc_now()
        self.reset_counters_if_needed(
            user_id,
            subscription_tier=subscription_tier,
            now=current,
        )
        reserved_prompts = max(int(reserved_prompts or 0), 0)
        enforce_daily_credit_limit = int(daily_credit_limit or 0) > 0
        enforce_monthly_token_limit = int(monthly_token_limit or 0) > 0
        max_daily_before = int(daily_credit_limit or 0) - max(int(reserved_credits or 0), 0)
        max_monthly_before = int(monthly_token_limit or 0) - max(int(reserved_tokens or 0), 0)
        if enforce_daily_credit_limit and max_daily_before < 0:
            return UsageReservationResult(False, "daily_credits")
        if enforce_monthly_token_limit and max_monthly_before < 0:
            return UsageReservationResult(False, "monthly_tokens")
        for _ in range(2):
            state = self.get_usage_state(user_id)
            daily_used = _int_value(state.get("ai_prompts_used_today"))
            weekly_used = _int_value(state.get("ai_prompts_used_week"))
            bonus_remaining = max(_int_value(state.get("admin_prompt_grants_remaining")), 0)
            reserved_quota_prompts, reserved_grant_prompts = _reserved_prompt_split(
                reserved_prompts=reserved_prompts,
                bonus_remaining=bonus_remaining,
            )
            max_daily_prompts_before = max(int(daily_prompt_limit or 0), 0) - reserved_quota_prompts
            max_weekly_prompts_before = max(int(weekly_prompt_limit or 0), 0) - reserved_quota_prompts
            if max_daily_prompts_before < 0:
                return UsageReservationResult(False, "daily_prompts")
            if max_weekly_prompts_before < 0:
                return UsageReservationResult(False, "weekly_prompts")

            values = {
                ":reserved_quota_prompts": reserved_quota_prompts,
                ":reserved_credits": max(int(reserved_credits or 0), 0),
                ":reserved_tokens": max(int(reserved_tokens or 0), 0),
                ":max_daily_prompts_before": max_daily_prompts_before,
                ":max_weekly_prompts_before": max_weekly_prompts_before,
                ":today": _current_day_key(current),
                ":week": _current_week_key(current),
                ":month": _current_month_key(current),
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            }
            condition_parts = [
                "attribute_exists(user_id)",
                "ai_prompts_day_reset = :today",
                "ai_prompts_week_reset = :week",
                "ai_last_reset = :today",
                "ai_tokens_month_reset = :month",
                "ai_prompts_used_today <= :max_daily_prompts_before",
                "ai_prompts_used_week <= :max_weekly_prompts_before",
            ]
            if reserved_grant_prompts > 0:
                values[":reserved_grant_prompts"] = reserved_grant_prompts
                condition_parts.append("attribute_exists(admin_prompt_grants_remaining)")
                condition_parts.append("admin_prompt_grants_remaining >= :reserved_grant_prompts")
            if enforce_daily_credit_limit:
                condition_parts.append("ai_credits_used_today <= :max_daily_before")
                values[":max_daily_before"] = max_daily_before
            if enforce_monthly_token_limit:
                condition_parts.append("ai_tokens_used_month <= :max_monthly_before")
                values[":max_monthly_before"] = max_monthly_before

            update_expression = (
                "SET ai_prompts_used_today = ai_prompts_used_today + :reserved_quota_prompts, "
                "ai_prompts_used_week = ai_prompts_used_week + :reserved_quota_prompts, "
                "ai_credits_used_today = ai_credits_used_today + :reserved_credits, "
                "ai_tokens_used_month = ai_tokens_used_month + :reserved_tokens, "
                "subscription_tier = :subscription_tier, "
                "updated_at = :updated_at"
            )
            if reserved_grant_prompts > 0:
                update_expression += (
                    ", admin_prompt_grants_remaining = "
                    "admin_prompt_grants_remaining - :reserved_grant_prompts"
                )
            try:
                self._state_table.update_item(
                    Key={"user_id": user_id},
                    UpdateExpression=update_expression,
                    ConditionExpression=(" AND ".join(condition_parts)),
                    ExpressionAttributeValues=values,
                )
                return UsageReservationResult(
                    True,
                    "",
                    reserved_quota_prompts=reserved_quota_prompts,
                    reserved_grant_prompts=reserved_grant_prompts,
                )
            except ClientError as exc:
                if exc.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
                    raise
                state = self.get_usage_state(user_id)
                if (
                    not state
                    or str(state.get("ai_prompts_day_reset") or "") != _current_day_key(current)
                    or str(state.get("ai_prompts_week_reset") or "") != _current_week_key(current)
                    or str(state.get("ai_last_reset") or "") != _current_day_key(current)
                    or str(state.get("ai_tokens_month_reset") or "") != _current_month_key(current)
                ):
                    self.reset_counters_if_needed(
                        user_id,
                        subscription_tier=subscription_tier,
                        now=current,
                    )
                    continue
                bonus_remaining = max(_int_value(state.get("admin_prompt_grants_remaining")), 0)
                prompt_failure = _prompt_limit_failure_reason(
                    daily_used=_int_value(state.get("ai_prompts_used_today")),
                    weekly_used=_int_value(state.get("ai_prompts_used_week")),
                    bonus_remaining=bonus_remaining,
                    reserved_prompts=reserved_prompts,
                    daily_prompt_limit=daily_prompt_limit,
                    weekly_prompt_limit=weekly_prompt_limit,
                )
                if prompt_failure:
                    return UsageReservationResult(False, prompt_failure)
                if (
                    enforce_daily_credit_limit
                    and _int_value(state.get("ai_credits_used_today")) > max_daily_before
                ):
                    return UsageReservationResult(False, "daily_credits")
                if (
                    enforce_monthly_token_limit
                    and _int_value(state.get("ai_tokens_used_month")) > max_monthly_before
                ):
                    return UsageReservationResult(False, "monthly_tokens")
                return UsageReservationResult(False, "daily_prompts")

        return UsageReservationResult(False, "daily_prompts")

    def finalize_usage(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        reserved_credits: int,
        reserved_tokens: int,
        reserved_prompts: int = 0,
        reserved_quota_prompts: int = 0,
        reserved_grant_prompts: int = 0,
        actual_credits: int,
        actual_tokens: int,
        actual_prompts: int = 0,
        now: datetime | None = None,
    ) -> None:
        safe_reserved_quota = max(int(reserved_quota_prompts or 0), 0)
        safe_reserved_grant = max(int(reserved_grant_prompts or 0), 0)
        safe_reserved_prompts = max(int(reserved_prompts or 0), 0)
        if safe_reserved_quota + safe_reserved_grant == 0 and safe_reserved_prompts > 0:
            safe_reserved_quota = safe_reserved_prompts
        prompt_delta = int(actual_prompts or 0) - safe_reserved_prompts
        credit_delta = int(actual_credits or 0) - int(reserved_credits or 0)
        token_delta = int(actual_tokens or 0) - int(reserved_tokens or 0)
        if prompt_delta == 0 and credit_delta == 0 and token_delta == 0:
            self._touch_state(user_id, subscription_tier=subscription_tier, now=now)
            return
        prompt_quota_delta = prompt_delta
        prompt_grant_delta = 0
        if prompt_delta < 0:
            prompt_quota_delta = -min(abs(prompt_delta), safe_reserved_quota)
            prompt_grant_delta = prompt_delta - prompt_quota_delta
        elif prompt_delta > 0:
            state = self.get_usage_state(user_id)
            prompt_quota_delta, prompt_grant_delta = _reserved_prompt_split(
                reserved_prompts=prompt_delta,
                bonus_remaining=_int_value(state.get("admin_prompt_grants_remaining")),
            )
        self._adjust_usage(
            user_id,
            subscription_tier=subscription_tier,
            prompt_quota_delta=prompt_quota_delta,
            prompt_grant_delta=prompt_grant_delta,
            credit_delta=credit_delta,
            token_delta=token_delta,
            now=now,
        )

    def release_usage(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        reserved_credits: int,
        reserved_tokens: int,
        reserved_prompts: int = 0,
        reserved_quota_prompts: int = 0,
        reserved_grant_prompts: int = 0,
        now: datetime | None = None,
    ) -> None:
        safe_reserved_quota = max(int(reserved_quota_prompts or 0), 0)
        safe_reserved_grant = max(int(reserved_grant_prompts or 0), 0)
        safe_reserved_prompts = max(int(reserved_prompts or 0), 0)
        if safe_reserved_quota + safe_reserved_grant == 0 and safe_reserved_prompts > 0:
            safe_reserved_quota = safe_reserved_prompts
        self._adjust_usage(
            user_id,
            subscription_tier=subscription_tier,
            prompt_quota_delta=-safe_reserved_quota,
            prompt_grant_delta=-safe_reserved_grant,
            credit_delta=-max(int(reserved_credits or 0), 0),
            token_delta=-max(int(reserved_tokens or 0), 0),
            now=now,
        )

    def get_prompt_limit_status(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        daily_prompt_limit: int,
        weekly_prompt_limit: int,
        now: datetime | None = None,
    ) -> dict[str, Any]:
        current = now or _utc_now()
        self.reset_counters_if_needed(
            user_id,
            subscription_tier=subscription_tier,
            now=current,
        )
        state = self.get_usage_state(user_id)
        daily_used = _int_value(state.get("ai_prompts_used_today"))
        weekly_used = _int_value(state.get("ai_prompts_used_week"))
        bonus_remaining = max(_int_value(state.get("admin_prompt_grants_remaining")), 0)
        daily_limit = max(int(daily_prompt_limit or 0), 0)
        weekly_limit = max(int(weekly_prompt_limit or 0), 0)
        daily_remaining = _prompt_quota_remaining(daily_used, daily_limit)
        weekly_remaining = _prompt_quota_remaining(weekly_used, weekly_limit)
        blocked_by = ""
        if bonus_remaining <= 0 and daily_remaining <= 0:
            blocked_by = "daily_prompts"
        elif bonus_remaining <= 0 and weekly_remaining <= 0:
            blocked_by = "weekly_prompts"

        return {
            "daily": {
                "used": daily_used,
                "limit": daily_limit,
                "remaining": daily_remaining,
                "resets_at": _utc_now_iso(_next_day_reset_at(current)),
            },
            "weekly": {
                "used": weekly_used,
                "limit": weekly_limit,
                "remaining": weekly_remaining,
                "resets_at": _utc_now_iso(_next_week_reset_at(current)),
            },
            "can_submit": blocked_by == "",
            "blocked_by": blocked_by,
            "extra_prompts_remaining": bonus_remaining,
            "extra_prompt_bank": {
                "remaining": bonus_remaining,
                "consumed_first": True,
            },
        }

    def log_usage_event(
        self,
        *,
        user_id: str,
        project_id: str = "",
        prompt_trace_id: str = "",
        request_id: str = "",
        feature: str,
        model: str,
        provider: str = "",
        prompt_tokens: int,
        completion_tokens: int,
        total_tokens: int,
        credits_charged: int,
        status: str,
        error_code: str = "",
        resolved_tool: str = "",
        provider_response_id: str = "",
        runtime_config_fingerprint: str = "",
        app_version: str = "",
        platform: str = "",
        proxy_handler_ms_total: int = 0,
        provider_roundtrip_ms: int = 0,
        response_normalize_ms: int = 0,
        created_at: datetime | None = None,
    ) -> None:
        if self._events_table is None:
            return

        current = created_at or _utc_now()
        item: dict[str, Any] = {
            "id": str(uuid4()),
            "record_type": "ai_usage_event",
            "user_id": user_id,
            "feature": feature,
            "model": model,
            "prompt_tokens": max(int(prompt_tokens or 0), 0),
            "completion_tokens": max(int(completion_tokens or 0), 0),
            "total_tokens": max(int(total_tokens or 0), 0),
            "credits_charged": max(int(credits_charged or 0), 0),
            "status": (status or "").strip() or "unknown",
            "created_at": _utc_now_iso(current),
        }
        if project_id:
            item["project_id"] = project_id
        if prompt_trace_id:
            item["prompt_trace_id"] = prompt_trace_id
        if request_id:
            item["request_id"] = request_id
        if provider:
            item["provider"] = provider
        if error_code:
            item["error_code"] = error_code
        if resolved_tool:
            item["resolved_tool"] = resolved_tool
        if provider_response_id:
            item["provider_response_id"] = provider_response_id
        if runtime_config_fingerprint:
            item["runtime_config_fingerprint"] = runtime_config_fingerprint
        if app_version:
            item["app_version"] = app_version
        if platform:
            item["platform"] = platform
        if proxy_handler_ms_total > 0:
            item["proxy_handler_ms_total"] = proxy_handler_ms_total
        if provider_roundtrip_ms > 0:
            item["provider_roundtrip_ms"] = provider_roundtrip_ms
        if response_normalize_ms > 0:
            item["response_normalize_ms"] = response_normalize_ms
        self._events_table.put_item(Item=item)

    def _touch_state(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        now: datetime | None = None,
    ) -> None:
        if self._state_table is None:
            return
        current = now or _utc_now()
        self._state_table.update_item(
            Key={"user_id": user_id},
            UpdateExpression="SET subscription_tier = :subscription_tier, updated_at = :updated_at",
            ConditionExpression="attribute_exists(user_id)",
            ExpressionAttributeValues={
                ":subscription_tier": subscription_tier,
                ":updated_at": _utc_now_iso(current),
            },
        )

    def _adjust_usage(
        self,
        user_id: str,
        *,
        subscription_tier: str,
        prompt_quota_delta: int,
        prompt_grant_delta: int,
        credit_delta: int,
        token_delta: int,
        now: datetime | None = None,
    ) -> None:
        if self._state_table is None:
            raise RuntimeError("AI usage state table is not configured.")

        current = now or _utc_now()
        expression_values: dict[str, Any] = {
            ":prompt_quota_delta": int(prompt_quota_delta or 0),
            ":credit_delta": int(credit_delta or 0),
            ":token_delta": int(token_delta or 0),
            ":subscription_tier": subscription_tier,
            ":updated_at": _utc_now_iso(current),
        }
        condition_parts = ["attribute_exists(user_id)"]
        update_parts = [
            "ai_prompts_used_today = ai_prompts_used_today + :prompt_quota_delta",
            "ai_prompts_used_week = ai_prompts_used_week + :prompt_quota_delta",
            "ai_credits_used_today = ai_credits_used_today + :credit_delta",
            "ai_tokens_used_month = ai_tokens_used_month + :token_delta",
            "subscription_tier = :subscription_tier",
            "updated_at = :updated_at",
        ]
        if prompt_quota_delta < 0:
            expression_values[":refundable_prompts_today"] = abs(prompt_quota_delta)
            expression_values[":refundable_prompts_week"] = abs(prompt_quota_delta)
            condition_parts.append("ai_prompts_used_today >= :refundable_prompts_today")
            condition_parts.append("ai_prompts_used_week >= :refundable_prompts_week")
        if credit_delta < 0:
            expression_values[":refundable_credits"] = abs(credit_delta)
            condition_parts.append("ai_credits_used_today >= :refundable_credits")
        if token_delta < 0:
            expression_values[":refundable_tokens"] = abs(token_delta)
            condition_parts.append("ai_tokens_used_month >= :refundable_tokens")
        if prompt_grant_delta > 0:
            expression_values[":grant_charge"] = prompt_grant_delta
            condition_parts.append("attribute_exists(admin_prompt_grants_remaining)")
            condition_parts.append("admin_prompt_grants_remaining >= :grant_charge")
            update_parts.append(
                "admin_prompt_grants_remaining = admin_prompt_grants_remaining - :grant_charge"
            )
        if prompt_grant_delta < 0:
            expression_values[":grant_refund"] = abs(prompt_grant_delta)
            expression_values[":zero"] = 0
            update_parts.append(
                "admin_prompt_grants_remaining = if_not_exists(admin_prompt_grants_remaining, :zero) + :grant_refund"
            )

        self._state_table.update_item(
            Key={"user_id": user_id},
            UpdateExpression=f"SET {', '.join(update_parts)}",
            ConditionExpression=" AND ".join(condition_parts),
            ExpressionAttributeValues=expression_values,
        )

    def _conditional_update(self, **kwargs: Any) -> None:
        if self._state_table is None:
            return
        try:
            self._state_table.update_item(**kwargs)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
                raise
