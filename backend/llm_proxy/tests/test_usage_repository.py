from __future__ import annotations

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common.usage_repository import AiUsageRepository  # noqa: E402


class _FakeStateTable:
    def __init__(self) -> None:
        self.last_update_kwargs: dict | None = None

    def update_item(self, **kwargs: object) -> dict:
        self.last_update_kwargs = dict(kwargs)
        return {}


class _FakeEntitlementsTable:
    def __init__(self, item: dict) -> None:
        self.item = item

    def get_item(self, **_kwargs: object) -> dict:
        return {"Item": dict(self.item)}


class _FakeCollaborationTable:
    def __init__(self, memberships: list[dict], organizations: dict[str, dict]) -> None:
        self.memberships = memberships
        self.organizations = organizations

    def query(self, **_kwargs: object) -> dict:
        return {"Items": [dict(item) for item in self.memberships]}

    def get_item(self, Key: dict, **_kwargs: object) -> dict:
        entity_id = str(Key.get("entity_id") or "")
        organization_id = entity_id.removeprefix("organization#")
        organization = self.organizations.get(organization_id)
        return {"Item": dict(organization)} if organization else {}


class UsageRepositoryTests(unittest.TestCase):
    def test_load_user_context_prefers_plan_code_over_legacy_tier(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = _FakeEntitlementsTable(
            {
                "user_id": "user-123",
                "tier": "pro",
                "plan_code": "starter",
                "status": "active",
                "limits": {
                    "ai_prompts_daily": 400,
                    "ai_prompts_weekly": 1500,
                },
            }
        )

        context = repo.load_user_context("user-123")

        self.assertEqual(context["subscription_tier"], "starter")
        self.assertEqual(context["tier"], "starter")
        self.assertEqual(context["limits"]["ai_prompts_daily"], 400)

    def test_load_user_context_uses_active_education_membership(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = _FakeEntitlementsTable(
            {
                "user_id": "user-123",
                "plan_code": "free",
                "status": "active",
            }
        )
        repo._collaboration_table = _FakeCollaborationTable(
            [
                {
                    "entity_type": "membership",
                    "user_id": "user-123",
                    "organization_id": "edu-1",
                    "status": "active",
                    "role": "student",
                }
            ],
            {
                "edu-1": {
                    "entity_type": "organization",
                    "organization_id": "edu-1",
                    "plan_code": "education",
                    "status": "active",
                }
            },
        )

        context = repo.load_user_context("user-123")

        self.assertEqual(context["subscription_tier"], "education")
        self.assertEqual(context["source_type"], "organization")

    def test_load_user_context_keeps_higher_personal_plan_over_education(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = _FakeEntitlementsTable(
            {
                "user_id": "user-123",
                "plan_code": "producer",
                "status": "active",
            }
        )
        repo._collaboration_table = _FakeCollaborationTable(
            [
                {
                    "entity_type": "membership",
                    "user_id": "user-123",
                    "organization_id": "edu-1",
                    "status": "active",
                    "role": "student",
                }
            ],
            {
                "edu-1": {
                    "entity_type": "organization",
                    "organization_id": "edu-1",
                    "plan_code": "education",
                    "status": "active",
                }
            },
        )

        context = repo.load_user_context("user-123")

        self.assertEqual(context["subscription_tier"], "producer")
        self.assertNotIn("source_type", context)

    def test_load_user_context_omits_paid_limits_for_inactive_entitlement(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = _FakeEntitlementsTable(
            {
                "user_id": "user-123",
                "plan_code": "producer",
                "status": "expired",
                "limits": {
                    "ai_prompts_daily": 1000,
                    "ai_prompts_weekly": 4000,
                },
            }
        )

        context = repo.load_user_context("user-123")

        self.assertEqual(context["subscription_tier"], "free")
        self.assertNotIn("limits", context)

    def test_load_user_context_omits_paid_limits_for_expired_active_entitlement(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = _FakeEntitlementsTable(
            {
                "user_id": "user-123",
                "plan_code": "starter",
                "status": "active",
                "expires_at": "2026-03-10T00:00:00+00:00",
                "limits": {
                    "ai_prompts_daily": 400,
                    "ai_prompts_weekly": 1500,
                },
            }
        )

        context = repo.load_user_context("user-123")

        self.assertEqual(context["subscription_tier"], "free")
        self.assertEqual(context["entitlement_status"], "expired")
        self.assertNotIn("limits", context)

    def test_reserve_usage_omits_unused_limit_placeholders(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = _FakeStateTable()
        repo._events_table = None
        repo._entitlements_table = None
        repo.reset_counters_if_needed = lambda *args, **kwargs: None
        repo.get_usage_state = lambda *args, **kwargs: {}

        result = repo.reserve_usage(
            "user-123",
            subscription_tier="free",
            reserved_credits=1,
            reserved_tokens=128,
            reserved_prompts=1,
            daily_credit_limit=0,
            monthly_token_limit=0,
            daily_prompt_limit=10,
            weekly_prompt_limit=20,
            now=datetime(2026, 3, 17, tzinfo=timezone.utc),
        )

        self.assertTrue(result.allowed)
        self.assertEqual(result.limit_reason, "")
        values = repo._state_table.last_update_kwargs["ExpressionAttributeValues"]
        self.assertNotIn(":max_daily_before", values)
        self.assertNotIn(":max_monthly_before", values)
        condition = repo._state_table.last_update_kwargs["ConditionExpression"]
        self.assertNotIn(":max_daily_before", condition)
        self.assertNotIn(":max_monthly_before", condition)

    def test_reserve_usage_includes_limit_placeholders_when_enforced(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = _FakeStateTable()
        repo._events_table = None
        repo._entitlements_table = None
        repo.reset_counters_if_needed = lambda *args, **kwargs: None
        repo.get_usage_state = lambda *args, **kwargs: {}

        result = repo.reserve_usage(
            "user-123",
            subscription_tier="pro",
            reserved_credits=1,
            reserved_tokens=128,
            reserved_prompts=1,
            daily_credit_limit=50,
            monthly_token_limit=10000,
            daily_prompt_limit=10,
            weekly_prompt_limit=20,
            now=datetime(2026, 3, 17, tzinfo=timezone.utc),
        )

        self.assertTrue(result.allowed)
        values = repo._state_table.last_update_kwargs["ExpressionAttributeValues"]
        self.assertIn(":max_daily_before", values)
        self.assertIn(":max_monthly_before", values)
        condition = repo._state_table.last_update_kwargs["ConditionExpression"]
        self.assertIn(":max_daily_before", condition)
        self.assertIn(":max_monthly_before", condition)

    def test_reserve_usage_consumes_admin_prompt_grants_when_prompt_limit_is_exceeded(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = _FakeStateTable()
        repo._events_table = None
        repo._entitlements_table = None
        repo.reset_counters_if_needed = lambda *args, **kwargs: None
        repo.get_usage_state = lambda *args, **kwargs: {
            "ai_prompts_used_today": 10,
            "ai_prompts_used_week": 20,
            "admin_prompt_grants_remaining": 3,
            "ai_prompts_day_reset": "2026-03-17",
            "ai_prompts_week_reset": "2026-03-16",
            "ai_last_reset": "2026-03-17",
            "ai_tokens_month_reset": "2026-03",
        }

        result = repo.reserve_usage(
            "user-123",
            subscription_tier="free",
            reserved_credits=0,
            reserved_tokens=0,
            reserved_prompts=1,
            daily_credit_limit=0,
            monthly_token_limit=0,
            daily_prompt_limit=10,
            weekly_prompt_limit=20,
            now=datetime(2026, 3, 17, tzinfo=timezone.utc),
        )

        self.assertTrue(result.allowed)
        values = repo._state_table.last_update_kwargs["ExpressionAttributeValues"]
        condition = repo._state_table.last_update_kwargs["ConditionExpression"]
        update = repo._state_table.last_update_kwargs["UpdateExpression"]
        self.assertEqual(result.reserved_grant_prompts, 1)
        self.assertEqual(result.reserved_quota_prompts, 0)
        self.assertEqual(values[":reserved_grant_prompts"], 1)
        self.assertEqual(values[":reserved_quota_prompts"], 0)
        self.assertIn("admin_prompt_grants_remaining >= :reserved_grant_prompts", condition)
        self.assertIn("admin_prompt_grants_remaining - :reserved_grant_prompts", update)

    def test_reserve_usage_still_uses_quota_when_no_bonus_bank_exists(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = _FakeStateTable()
        repo._events_table = None
        repo._entitlements_table = None
        repo.reset_counters_if_needed = lambda *args, **kwargs: None
        repo.get_usage_state = lambda *args, **kwargs: {
            "ai_prompts_used_today": 4,
            "ai_prompts_used_week": 12,
            "admin_prompt_grants_remaining": 0,
            "ai_prompts_day_reset": "2026-03-17",
            "ai_prompts_week_reset": "2026-03-16",
            "ai_last_reset": "2026-03-17",
            "ai_tokens_month_reset": "2026-03",
        }

        result = repo.reserve_usage(
            "user-123",
            subscription_tier="free",
            reserved_credits=0,
            reserved_tokens=0,
            reserved_prompts=1,
            daily_credit_limit=0,
            monthly_token_limit=0,
            daily_prompt_limit=10,
            weekly_prompt_limit=20,
            now=datetime(2026, 3, 17, tzinfo=timezone.utc),
        )

        self.assertTrue(result.allowed)
        self.assertEqual(result.reserved_grant_prompts, 0)
        self.assertEqual(result.reserved_quota_prompts, 1)

    def test_get_prompt_limit_status_includes_admin_prompt_grants_in_remaining(self) -> None:
        repo = object.__new__(AiUsageRepository)
        repo._state_table = None
        repo._events_table = None
        repo._entitlements_table = None
        repo.reset_counters_if_needed = lambda *args, **kwargs: None
        repo.get_usage_state = lambda *args, **kwargs: {
            "ai_prompts_used_today": 50,
            "ai_prompts_used_week": 350,
            "admin_prompt_grants_remaining": 2,
        }

        status = repo.get_prompt_limit_status(
            "user-123",
            subscription_tier="free",
            daily_prompt_limit=50,
            weekly_prompt_limit=350,
            now=datetime(2026, 3, 17, tzinfo=timezone.utc),
        )

        self.assertTrue(status["can_submit"])
        self.assertEqual(status["daily"]["remaining"], 0)
        self.assertEqual(status["weekly"]["remaining"], 0)
        self.assertEqual(status["extra_prompts_remaining"], 2)
        self.assertEqual(status["extra_prompt_bank"]["remaining"], 2)
        self.assertTrue(status["extra_prompt_bank"]["consumed_first"])


if __name__ == "__main__":
    unittest.main()
