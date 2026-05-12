import importlib
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from support import FakeBillingRepo

module = importlib.import_module("src.handlers.reconcile")


class ReconcileTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.collaboration_repo = mock.Mock()
        self.original_repo = module.repo
        self.original_collaboration_repo = module.collaboration_repo
        module.repo = self.repo
        module.collaboration_repo = self.collaboration_repo

    def tearDown(self):
        module.repo = self.original_repo
        module.collaboration_repo = self.original_collaboration_repo

    def test_expired_current_subscription_downgrades_entitlement(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "google",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2026-03-01T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-1",
                "capabilities": {"all_plugins": True},
                "management_channel": "google",
                "revision": 4,
            }
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.subscriptions["sub-1"]["status"], "expired")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "free")
        self.assertEqual(entitlement["revision"], 5)
        self.assertEqual(self.repo.reconciliation_jobs[0]["downgraded"], 1)

    def test_recently_expired_mobile_subscription_waits_for_store_webhook(self):
        expires_at = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()
        self.repo.upsert_subscription(
            {
                "subscription_id": "apple-sub",
                "user_id": "user-1",
                "provider": "apple",
                "plan_code": "starter",
                "status": "active",
                "expires_at": expires_at,
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "starter",
                "status": "active",
                "source_provider": "apple",
                "source_subscription_id": "apple-sub",
                "capabilities": {"cloud_projects": True},
                "management_channel": "apple",
                "revision": 4,
            }
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.subscriptions["apple-sub"]["status"], "active")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "starter")
        self.assertEqual(entitlement["revision"], 4)
        self.assertEqual(self.repo.reconciliation_jobs[0]["downgraded"], 0)

    def test_non_current_entitlement_is_not_downgraded(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "google",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2026-03-01T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-2",
                "capabilities": {"all_plugins": True},
                "management_channel": "google",
                "revision": 9,
            }
        )

        module.handler({}, object())

        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["source_subscription_id"], "sub-2")
        self.assertEqual(entitlement["revision"], 9)
        self.assertEqual(self.repo.reconciliation_jobs[0]["downgraded"], 0)

    def test_expired_current_subscription_falls_back_to_other_active_subscription(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "studio-sub",
                "user_id": "user-1",
                "provider": "paddle",
                "plan_code": "studio",
                "status": "active",
                "expires_at": "2026-03-01T00:00:00+00:00",
            }
        )
        self.repo.upsert_subscription(
            {
                "subscription_id": "producer-sub",
                "user_id": "user-1",
                "provider": "google",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2099-03-01T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "paddle",
                "source_subscription_id": "studio-sub",
                "capabilities": {"studio_features": True},
                "management_channel": "paddle",
                "revision": 7,
            }
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "producer")
        self.assertEqual(entitlement["source_subscription_id"], "producer-sub")
        self.assertEqual(entitlement["revision"], 8)
        self.collaboration_repo.sync_organization_for_subscription.assert_called_once()
        synced = self.collaboration_repo.sync_organization_for_subscription.call_args.args[0]
        self.assertEqual(synced["subscription_id"], "studio-sub")
        self.assertEqual(synced["status"], "expired")


if __name__ == "__main__":
    unittest.main()
