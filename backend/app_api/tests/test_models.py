import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src.common.models import (
    choose_primary_subscription,
    default_capabilities_for_tier,
    entitlement_capabilities_for_status,
    free_entitlement,
    infer_tier_from_product_id,
    subscription_priority_key,
    status_has_active_access,
)


class ModelTests(unittest.TestCase):
    def test_free_capabilities_default(self):
        caps = default_capabilities_for_tier("free", allow_studio_tier=False)
        self.assertFalse(caps["pro_editor"])
        self.assertTrue(caps["video_projects"])

    def test_pro_capabilities(self):
        caps = default_capabilities_for_tier("pro", allow_studio_tier=False)
        self.assertTrue(caps["pro_editor"])
        self.assertTrue(caps["premium_effects"])

    def test_inactive_status_removes_paid_capabilities(self):
        caps = entitlement_capabilities_for_status(
            "pro",
            "expired",
            allow_studio_tier=False,
        )
        self.assertFalse(caps["pro_editor"])
        self.assertFalse(caps["premium_effects"])

    def test_active_access_statuses(self):
        self.assertTrue(status_has_active_access("trialing"))
        self.assertTrue(status_has_active_access("active"))
        self.assertTrue(status_has_active_access("grace_period"))
        self.assertFalse(status_has_active_access("expired"))

    def test_infer_tier_from_product_id(self):
        self.assertEqual(infer_tier_from_product_id("mixroom_pro_monthly"), "pro")
        self.assertEqual(infer_tier_from_product_id("mixroom_studio_monthly"), "studio")
        self.assertEqual(infer_tier_from_product_id("basic"), "free")

    def test_free_entitlement_shape(self):
        snapshot = free_entitlement("u-1", allow_studio_tier=False).to_dict()
        self.assertEqual(snapshot["user_id"], "u-1")
        self.assertEqual(snapshot["tier"], "free")
        self.assertEqual(snapshot["plan_code"], "free")

    def test_primary_subscription_prefers_active_over_later_expired(self):
        choice = choose_primary_subscription(
            [
                {
                    "subscription_id": "expired-google",
                    "provider": "google",
                    "tier": "pro",
                    "status": "expired",
                    "expires_at": "2026-02-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-01T00:00:00+00:00",
                },
                {
                    "subscription_id": "active-apple",
                    "provider": "apple",
                    "tier": "pro",
                    "status": "active",
                    "expires_at": "2026-04-01T00:00:00+00:00",
                    "source_occurred_at": "2026-02-15T00:00:00+00:00",
                },
            ]
        )
        self.assertIsNotNone(choice)
        self.assertEqual(choice["subscription_id"], "active-apple")

    def test_primary_subscription_prefers_higher_tier_when_both_active(self):
        choice = choose_primary_subscription(
            [
                {
                    "subscription_id": "pro-sub",
                    "provider": "apple",
                    "tier": "pro",
                    "status": "active",
                    "expires_at": "2026-05-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-01T00:00:00+00:00",
                },
                {
                    "subscription_id": "studio-sub",
                    "provider": "google",
                    "tier": "studio",
                    "status": "grace_period",
                    "expires_at": "2026-04-15T00:00:00+00:00",
                    "source_occurred_at": "2026-03-02T00:00:00+00:00",
                },
            ]
        )
        self.assertIsNotNone(choice)
        self.assertEqual(choice["subscription_id"], "studio-sub")

    def test_subscription_priority_key_uses_activity_time_as_tiebreaker(self):
        older = {
            "subscription_id": "older",
            "tier": "pro",
            "status": "active",
            "expires_at": "2026-04-01T00:00:00+00:00",
            "source_occurred_at": "2026-03-01T00:00:00+00:00",
        }
        newer = {
            "subscription_id": "newer",
            "tier": "pro",
            "status": "active",
            "expires_at": "2026-04-01T00:00:00+00:00",
            "source_occurred_at": "2026-03-05T00:00:00+00:00",
        }
        self.assertGreater(subscription_priority_key(newer), subscription_priority_key(older))


if __name__ == "__main__":
    unittest.main()
