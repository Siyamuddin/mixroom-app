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
        self.original_load_provider_api_key = module.load_provider_api_key
        self.original_charge_toss_billing_key = module.charge_toss_billing_key
        self.original_send_auth_email = module.send_auth_email
        module.repo = self.repo
        module.collaboration_repo = self.collaboration_repo
        module.send_auth_email = mock.Mock()

    def tearDown(self):
        module.repo = self.original_repo
        module.collaboration_repo = self.original_collaboration_repo
        module.load_provider_api_key = self.original_load_provider_api_key
        module.charge_toss_billing_key = self.original_charge_toss_billing_key
        module.send_auth_email = self.original_send_auth_email

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

    def test_due_toss_subscription_renews_and_extends_entitlement(self):
        now = datetime.now(timezone.utc)
        due_at = (now - timedelta(minutes=5)).isoformat()
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-sub",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "studio",
                "product_code": "studio_monthly",
                "status": "active",
                "expires_at": due_at,
                "next_billed_at": due_at,
                "billing_key_parameter_name": "/mixroom/payment-credentials/test/toss/customer-1",
                "customer_id": "customer-1",
                "billing_amount": 149000,
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "toss",
                "source_subscription_id": "toss-sub",
                "revision": 1,
            }
        )
        module.load_provider_api_key = mock.Mock(return_value="billing-key-1")
        module.charge_toss_billing_key = mock.Mock(
            return_value={"status": "DONE", "card": {"company": "Visa", "number": "123456******4242"}}
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.reconciliation_jobs[0]["renewed"], 1)
        sub = self.repo.subscriptions["toss-sub"]
        self.assertEqual(sub["status"], "active")
        self.assertGreater(sub["next_billed_at"], due_at)
        entitlement = self.repo.entitlements["user-1"]
        self.assertEqual(entitlement["status"], "active")
        self.assertEqual(entitlement["payment_method"]["last4"], "4242")

    def test_failed_toss_renewal_enters_grace_instead_of_expiring_immediately(self):
        now = datetime.now(timezone.utc)
        due_at = (now - timedelta(minutes=5)).isoformat()
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-sub",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "studio",
                "product_code": "studio_monthly",
                "status": "active",
                "expires_at": due_at,
                "next_billed_at": due_at,
                "billing_key_secret_arn": "arn:toss-billing-key",
                "customer_id": "customer-1",
                "billing_amount": 149000,
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "toss",
                "source_subscription_id": "toss-sub",
                "revision": 1,
            }
        )
        module.load_provider_api_key = mock.Mock(return_value="billing-key-1")
        module.charge_toss_billing_key = mock.Mock(return_value={"status": "FAILED"})

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.reconciliation_jobs[0]["renewed"], 0)
        sub = self.repo.subscriptions["toss-sub"]
        self.assertEqual(sub["status"], "grace_period")
        self.assertGreater(sub["expires_at"], now.isoformat())
        self.assertEqual(self.repo.entitlements["user-1"]["status"], "grace_period")

    def test_healthy_recurring_subscription_does_not_send_expiry_notice(self):
        now = datetime.now(timezone.utc)
        self.repo.upsert_subscription(
            {
                "subscription_id": "paddle-sub",
                "user_id": "user-1",
                "provider": "paddle",
                "plan_code": "producer",
                "status": "active",
                "expires_at": (now + timedelta(days=6)).isoformat(),
                "next_billed_at": (now + timedelta(days=6)).isoformat(),
                "customer_email": "user@example.com",
            }
        )

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 200)
        module.send_auth_email.assert_not_called()
        self.assertEqual(self.repo.reconciliation_jobs[0]["notifications_sent"], 0)

    def test_canceling_subscription_gets_one_ending_notice(self):
        now = datetime.now(timezone.utc)
        self.repo.upsert_subscription(
            {
                "subscription_id": "paddle-sub",
                "user_id": "user-1",
                "provider": "paddle",
                "plan_code": "producer",
                "status": "active",
                "expires_at": (now + timedelta(days=6)).isoformat(),
                "next_billed_at": None,
                "cancel_at_period_end": True,
                "customer_email": "user@example.com",
            }
        )

        module.handler({}, object())
        module.handler({}, object())

        self.assertEqual(module.send_auth_email.call_count, 1)
        args = module.send_auth_email.call_args.kwargs
        self.assertEqual(args["to_email"], "user@example.com")
        self.assertIn("ending soon", args["subject"])
        notice_jobs = [
            item for item in self.repo.reconciliation_jobs
            if item.get("job_type") == "billing_notification"
        ]
        self.assertEqual(len(notice_jobs), 1)
        self.assertEqual(notice_jobs[0]["notice_type"], "ending_7d")

    def test_toss_one_time_subscription_gets_fixed_term_notice(self):
        now = datetime.now(timezone.utc)
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-one-time",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "starter",
                "status": "active",
                "expires_at": (now + timedelta(hours=20)).isoformat(),
                "next_billed_at": None,
                "customer_email": "user@example.com",
            }
        )

        module.handler({}, object())

        self.assertEqual(module.send_auth_email.call_count, 1)
        notice_jobs = [
            item for item in self.repo.reconciliation_jobs
            if item.get("job_type") == "billing_notification"
        ]
        self.assertEqual(notice_jobs[0]["notice_type"], "ending_1d")

    def test_payment_problem_notice_is_sent_once(self):
        now = datetime.now(timezone.utc)
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-sub",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "studio",
                "status": "grace_period",
                "expires_at": (now + timedelta(days=3)).isoformat(),
                "customer_email": "user@example.com",
            }
        )

        module.handler({}, object())
        module.handler({}, object())

        self.assertEqual(module.send_auth_email.call_count, 1)
        args = module.send_auth_email.call_args.kwargs
        self.assertIn("payment", args["subject"].lower())
        notice_jobs = [
            item for item in self.repo.reconciliation_jobs
            if item.get("job_type") == "billing_notification"
        ]
        self.assertEqual(len(notice_jobs), 1)
        self.assertEqual(notice_jobs[0]["notice_type"], "payment_problem")

if __name__ == "__main__":
    unittest.main()
