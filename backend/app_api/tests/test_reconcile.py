import importlib
import unittest

from support import FakeBillingRepo

module = importlib.import_module("src.handlers.reconcile")


class ReconcileTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.original_repo = module.repo
        module.repo = self.repo

    def tearDown(self):
        module.repo = self.original_repo

    def test_expired_current_subscription_downgrades_entitlement(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "google",
                "tier": "pro",
                "status": "active",
                "expires_at": "2026-03-01T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "pro",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-1",
                "capabilities": {"pro_editor": True},
                "management_channel": "google",
                "revision": 4,
            }
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.subscriptions["sub-1"]["status"], "expired")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["tier"], "free")
        self.assertEqual(entitlement["revision"], 5)
        self.assertEqual(self.repo.reconciliation_jobs[0]["downgraded"], 1)

    def test_non_current_entitlement_is_not_downgraded(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "google",
                "tier": "pro",
                "status": "active",
                "expires_at": "2026-03-01T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "tier": "pro",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-2",
                "capabilities": {"pro_editor": True},
                "management_channel": "google",
                "revision": 9,
            }
        )

        module.handler({}, object())

        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["source_subscription_id"], "sub-2")
        self.assertEqual(entitlement["revision"], 9)
        self.assertEqual(self.repo.reconciliation_jobs[0]["downgraded"], 0)


if __name__ == "__main__":
    unittest.main()
