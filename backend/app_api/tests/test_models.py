import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src.common.models import (
    choose_primary_subscription,
    default_capabilities_for_plan,
    default_limits_for_plan,
    entitlement_capabilities_for_status,
    free_entitlement,
    subscription_priority_key,
    subscription_effective_status,
    status_has_active_access,
)


class ModelTests(unittest.TestCase):
    def test_free_capabilities_default(self):
        caps = default_capabilities_for_plan("free")
        self.assertFalse(caps["all_plugins"])
        self.assertTrue(caps["video_projects"])

    def test_producer_capabilities(self):
        caps = default_capabilities_for_plan("producer")
        self.assertTrue(caps["all_plugins"])
        self.assertTrue(caps["advanced_ai_models"])

    def test_studio_capabilities_are_team_plan_capabilities(self):
        caps = default_capabilities_for_plan("studio")
        self.assertTrue(caps["all_plugins"])
        self.assertTrue(caps["team_workspaces"])
        self.assertTrue(caps["cloud_projects"])

    def test_inactive_status_removes_paid_capabilities(self):
        caps = entitlement_capabilities_for_status(
            "producer",
            "expired",
        )
        self.assertFalse(caps["all_plugins"])
        self.assertFalse(caps["advanced_ai_models"])

    def test_active_access_statuses(self):
        self.assertTrue(status_has_active_access("trialing"))
        self.assertTrue(status_has_active_access("active"))
        self.assertTrue(status_has_active_access("grace_period"))
        self.assertTrue(status_has_active_access("past_due"))
        self.assertFalse(status_has_active_access("expired"))

    def test_subscription_effective_status_uses_current_period_end(self):
        self.assertEqual(
            subscription_effective_status(
                {
                    "status": "active",
                    "current_period_end": "2026-01-01T00:00:00+00:00",
                }
            ),
            "expired",
        )

    def test_free_entitlement_shape(self):
        snapshot = free_entitlement("u-1").to_dict()
        self.assertEqual(snapshot["user_id"], "u-1")
        self.assertEqual(snapshot["tier"], "free")
        self.assertEqual(snapshot["plan_code"], "free")
        self.assertEqual(snapshot["limits"]["cloud_projects"], 1)
        self.assertEqual(snapshot["limits"]["ai_prompts_daily"], 200)
        self.assertEqual(snapshot["limits"]["ai_prompts_weekly"], 600)

    def test_plan_limits_include_weekly_prompt_caps(self):
        self.assertEqual(default_limits_for_plan("starter")["ai_prompts_weekly"], 1500)
        self.assertEqual(default_limits_for_plan("producer")["ai_prompts_weekly"], 4000)

    def test_primary_subscription_prefers_active_over_later_expired(self):
        choice = choose_primary_subscription(
            [
                {
                    "subscription_id": "expired-google",
                    "provider": "google",
                    "plan_code": "producer",
                    "status": "expired",
                    "expires_at": "2026-02-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-01T00:00:00+00:00",
                },
                {
                    "subscription_id": "active-apple",
                    "provider": "apple",
                    "plan_code": "producer",
                    "status": "active",
                    "expires_at": "2099-04-01T00:00:00+00:00",
                    "source_occurred_at": "2026-02-15T00:00:00+00:00",
                },
            ]
        )
        self.assertIsNotNone(choice)
        self.assertEqual(choice["subscription_id"], "active-apple")

    def test_primary_subscription_prefers_higher_plan_when_both_active(self):
        choice = choose_primary_subscription(
            [
                {
                    "subscription_id": "pro-sub",
                    "provider": "apple",
                    "plan_code": "producer",
                    "status": "active",
                    "expires_at": "2099-05-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-01T00:00:00+00:00",
                },
                {
                    "subscription_id": "studio-sub",
                    "provider": "google",
                    "plan_code": "studio",
                    "status": "grace_period",
                    "expires_at": "2099-04-15T00:00:00+00:00",
                    "source_occurred_at": "2026-03-02T00:00:00+00:00",
                },
            ]
        )
        self.assertIsNotNone(choice)
        self.assertEqual(choice["subscription_id"], "studio-sub")

    def test_subscription_priority_key_uses_activity_time_as_tiebreaker(self):
        older = {
            "subscription_id": "older",
            "plan_code": "producer",
            "status": "active",
            "expires_at": "2099-04-01T00:00:00+00:00",
            "source_occurred_at": "2026-03-01T00:00:00+00:00",
        }
        newer = {
            "subscription_id": "newer",
            "plan_code": "producer",
            "status": "active",
            "expires_at": "2099-04-01T00:00:00+00:00",
            "source_occurred_at": "2026-03-05T00:00:00+00:00",
        }
        self.assertGreater(subscription_priority_key(newer), subscription_priority_key(older))

    def test_primary_subscription_ignores_stale_active_status_after_expiry(self):
        choice = choose_primary_subscription(
            [
                {
                    "subscription_id": "old-producer",
                    "provider": "google",
                    "plan_code": "producer",
                    "status": "active",
                    "expires_at": "2026-01-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-01T00:00:00+00:00",
                },
                {
                    "subscription_id": "current-starter",
                    "provider": "google",
                    "plan_code": "starter",
                    "status": "active",
                    "expires_at": "2099-01-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-02T00:00:00+00:00",
                },
            ]
        )
        self.assertIsNotNone(choice)
        self.assertEqual(choice["subscription_id"], "current-starter")


if __name__ == "__main__":
    unittest.main()
