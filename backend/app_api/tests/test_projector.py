import importlib
import json
import unittest

from support import FakeBillingRepo, FakeEventBridge

module = importlib.import_module("src.handlers.projector")


class ProjectorTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.eventbridge = FakeEventBridge()
        self.original_repo = module.repo
        self.original_eventbridge = module.eventbridge
        module.repo = self.repo
        module.eventbridge = self.eventbridge

    def tearDown(self):
        module.repo = self.original_repo
        module.eventbridge = self.original_eventbridge

    def test_apply_projection_updates_subscription_and_entitlement(self):
        result = module._apply_projection(
            {
                "event_id": "google:event-1",
                "provider": "google",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "tier": "pro",
                    "status": "active",
                    "expires_at": "2026-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "google",
                    "product_id": "mixroom_pro_monthly",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["tier"], "pro")
        self.assertEqual(entitlement["status"], "active")
        self.assertEqual(entitlement["source_subscription_id"], "sub-1")
        self.assertEqual(len(self.eventbridge.entries), 1)
        detail = json.loads(self.eventbridge.entries[0]["Detail"])
        self.assertEqual(detail["revision"], 1)

    def test_stale_event_is_ignored(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "pro",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-new",
                "capabilities": {"pro_editor": True},
                "management_channel": "google",
                "source_occurred_at": "2026-03-22T00:00:00+00:00",
                "revision": 7,
            }
        )

        result = module._apply_projection(
            {
                "event_id": "google:event-old",
                "provider": "google",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-old",
                    "tier": "free",
                    "status": "expired",
                },
            }
        )

        self.assertEqual(result, "ignored_stale_event")
        self.assertEqual(self.repo.get_entitlement("user-1")["revision"], 7)
        self.assertEqual(self.eventbridge.entries, [])

    def test_higher_active_subscription_wins(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "studio-sub",
                "user_id": "user-1",
                "provider": "apple",
                "tier": "studio",
                "status": "grace_period",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2026-04-25T00:00:00+00:00",
                "source_occurred_at": "2026-03-21T00:00:00+00:00",
                "management_channel": "apple",
                "updated_at": "2026-03-21T00:00:00+00:00",
            }
        )

        result = module._apply_projection(
            {
                "event_id": "google:event-2",
                "provider": "google",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "google",
                    "subscription_id": "pro-sub",
                    "tier": "pro",
                    "status": "active",
                    "expires_at": "2026-04-20T00:00:00+00:00",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["tier"], "studio")
        self.assertEqual(entitlement["status"], "grace_period")
        self.assertEqual(entitlement["source_subscription_id"], "studio-sub")

    def test_handler_marks_event_processed(self):
        self.repo.put_billing_event_if_new(
            {
                "event_id": "apple:event-1",
                "provider": "apple",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "sub-1",
                    "tier": "pro",
                    "status": "active",
                },
            }
        )

        response = module.handler(
            {"Records": [{"body": json.dumps({"event_id": "apple:event-1"})}]},
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(
            self.repo.get_billing_event("apple:event-1")["processing_result"],
            "projected",
        )


if __name__ == "__main__":
    unittest.main()
