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


class UsageRepositoryTests(unittest.TestCase):
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
        self.assertEqual(values[":required_bonus_prompts"], 1)
        self.assertIn("admin_prompt_grants_remaining >= :required_bonus_prompts", condition)
        self.assertIn("admin_prompt_grants_remaining - :required_bonus_prompts", update)

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
        self.assertEqual(status["daily"]["remaining"], 2)
        self.assertEqual(status["weekly"]["remaining"], 2)
        self.assertEqual(status["extra_prompts_remaining"], 2)


if __name__ == "__main__":
    unittest.main()
