import importlib
import json
import unittest

from support import FakeBillingRepo, FakeEventBridge

module = importlib.import_module("src.handlers.projector")


class ProjectorTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.eventbridge = FakeEventBridge()
        self.collaboration_repo = unittest.mock.Mock()
        self.original_repo = module.repo
        self.original_eventbridge = module.eventbridge
        self.original_collaboration_repo = module.collaboration_repo
        module.repo = self.repo
        module.eventbridge = self.eventbridge
        module.collaboration_repo = self.collaboration_repo

    def tearDown(self):
        module.repo = self.original_repo
        module.eventbridge = self.original_eventbridge
        module.collaboration_repo = self.original_collaboration_repo

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
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "google",
                    "product_id": "mixroom_producer_monthly",
                    "product_code": "producer_monthly",
                    "plan_code": "producer",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["status"], "active")
        self.assertEqual(entitlement["source_subscription_id"], "sub-1")
        self.assertEqual(entitlement["plan_code"], "producer")
        self.assertEqual(entitlement["product_code"], "producer_monthly")
        self.assertEqual(len(self.eventbridge.entries), 1)
        detail = json.loads(self.eventbridge.entries[0]["Detail"])
        self.assertEqual(detail["revision"], 1)

    def test_studio_projection_syncs_linked_organization_lifecycle(self):
        result = module._apply_projection(
            {
                "event_id": "paddle:studio-event",
                "provider": "paddle",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "studio-sub",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "management_channel": "web",
                    "product_code": "studio_monthly",
                    "plan_code": "studio",
                    "seat_count": 7,
                    "extra_storage_tb": 1,
                    "next_billed_at": "2026-04-20T00:00:00+00:00",
                },
            }
        )

        self.assertEqual(result, "projected")
        self.collaboration_repo.sync_organization_for_subscription.assert_called_once()
        synced = self.collaboration_repo.sync_organization_for_subscription.call_args.args[0]
        self.assertEqual(synced["subscription_id"], "studio-sub")
        self.assertEqual(synced["plan_code"], "studio")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "studio")
        self.assertEqual(entitlement["source_subscription_id"], "studio-sub")
        self.assertEqual(entitlement["seat_count"], 7)
        self.assertEqual(entitlement["extra_storage_tb"], 1)
        self.assertEqual(entitlement["next_billed_at"], "2026-04-20T00:00:00+00:00")
        self.assertEqual(entitlement["limit_overrides"]["members"], 7)
        self.assertEqual(entitlement["limit_overrides"]["shared_storage_gb"], 2048)

    def test_paddle_ignores_non_subscription_noise_events(self):
        result = module._apply_projection(
            {
                "event_id": "paddle:address-created",
                "provider": "paddle",
                "user_id": "user-1",
                "event_type": "address.created",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "add_123",
                    "status": "active",
                    "plan_code": "producer",
                },
            }
        )

        self.assertEqual(result, "ignored_non_subscription_event")
        self.assertEqual(self.repo.subscriptions, {})
        self.assertIsNone(self.repo.get_entitlement("user-1"))

    def test_paddle_transaction_completed_preserves_subscription_billing_date(self):
        module._apply_projection(
            {
                "event_id": "paddle:subscription-created",
                "provider": "paddle",
                "user_id": "user-1",
                "event_type": "subscription.created",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "sub_123",
                    "status": "active",
                    "plan_code": "producer",
                    "product_code": "producer_monthly",
                    "next_billed_at": "2026-04-20T00:00:00+00:00",
                },
            }
        )

        result = module._apply_projection(
            {
                "event_id": "paddle:transaction-completed",
                "provider": "paddle",
                "user_id": "user-1",
                "event_type": "transaction.completed",
                "occurred_at": "2026-03-20T00:01:00+00:00",
                "created_at": "2026-03-20T00:01:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "sub_123",
                    "status": "active",
                    "plan_code": "producer",
                    "product_code": "producer_monthly",
                    "next_billed_at": None,
                },
            }
        )

        self.assertEqual(result, "projected")
        subscription = self.repo.get_subscription("sub_123")
        self.assertEqual(subscription["next_billed_at"], "2026-04-20T00:00:00+00:00")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["next_billed_at"], "2026-04-20T00:00:00+00:00")

    def test_studio_projection_removes_addon_overrides_on_quantity_decrease(self):
        module._apply_projection(
            {
                "event_id": "paddle:studio-event-1",
                "provider": "paddle",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "studio-sub",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "product_code": "studio_monthly",
                    "plan_code": "studio",
                    "seat_count": 8,
                    "extra_storage_tb": 2,
                },
            }
        )

        module._apply_projection(
            {
                "event_id": "paddle:studio-event-2",
                "provider": "paddle",
                "user_id": "user-1",
                "occurred_at": "2026-03-21T00:00:00+00:00",
                "created_at": "2026-03-21T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "studio-sub",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "product_code": "studio_monthly",
                    "plan_code": "studio",
                    "seat_count": 5,
                    "extra_storage_tb": 0,
                },
            }
        )

        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["seat_count"], 5)
        self.assertEqual(entitlement["extra_storage_tb"], 0)
        self.assertEqual(entitlement["limit_overrides"]["members"], 5)
        self.assertNotIn("shared_storage_gb", entitlement["limit_overrides"])

    def test_refunded_current_subscription_falls_back_to_active_subscription(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "google-sub",
                "user_id": "user-1",
                "provider": "google",
                "plan_code": "starter",
                "status": "active",
                "expires_at": "2099-04-20T00:00:00+00:00",
                "updated_at": "2026-03-19T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "source_provider": "paddle",
                "source_subscription_id": "paddle-sub",
                "capabilities": {"all_plugins": True},
                "management_channel": "web",
                "revision": 1,
            }
        )

        result = module._apply_projection(
            {
                "event_id": "paddle:refund",
                "provider": "paddle",
                "user_id": "user-1",
                "occurred_at": "2026-03-21T00:00:00+00:00",
                "created_at": "2026-03-21T00:00:01+00:00",
                "normalized": {
                    "provider": "paddle",
                    "subscription_id": "paddle-sub",
                    "status": "refunded",
                    "product_code": "producer_monthly",
                    "plan_code": "producer",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["source_subscription_id"], "google-sub")
        self.assertEqual(entitlement["plan_code"], "starter")
        self.assertEqual(entitlement["status"], "active")

    def test_reclaimed_subscription_expires_prior_user_entitlement(self):
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "producer",
                "status": "expired",
                "source_provider": "apple",
                "source_subscription_id": "orig-1",
                "capabilities": {"all_plugins": False},
                "management_channel": "apple",
                "revision": 4,
            }
        )

        result = module._apply_projection(
            {
                "event_id": "apple:event-reclaim",
                "provider": "apple",
                "user_id": "new-user",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "orig-1",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "apple",
                    "product_id": "mixroom_producer_monthly",
                    "product_code": "producer_monthly",
                    "plan_code": "producer",
                    "reclaimed_from_user_id": "old-user",
                },
            }
        )

        self.assertEqual(result, "projected")
        self.assertEqual(
            self.repo.get_entitlement("new-user")["source_subscription_id"],
            "orig-1",
        )
        prior = self.repo.get_entitlement("old-user")
        self.assertEqual(prior["plan_code"], "free")
        self.assertEqual(prior["source_subscription_id"], "free-default")
        self.assertEqual(prior["revision"], 5)

    def test_uses_current_subscription_when_user_index_lags(self):
        original_list = self.repo.list_subscriptions_for_user
        self.repo.list_subscriptions_for_user = lambda user_id: []
        self.addCleanup(setattr, self.repo, "list_subscriptions_for_user", original_list)

        result = module._apply_projection(
            {
                "event_id": "apple:event-1",
                "provider": "apple",
                "user_id": "user-1",
                "occurred_at": "2026-03-20T00:00:00+00:00",
                "created_at": "2026-03-20T00:00:01+00:00",
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "sub-1",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "apple",
                    "product_id": "mixroom_starter_monthly",
                    "product_code": "starter_monthly",
                    "plan_code": "starter",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "starter")
        self.assertEqual(entitlement["source_subscription_id"], "sub-1")

    def test_uses_current_subscription_when_user_index_returns_stale_copy(self):
        original_list = self.repo.list_subscriptions_for_user
        self.repo.list_subscriptions_for_user = lambda user_id: [
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "apple",
                "plan_code": "starter",
                "status": "active",
                "effective_at": "2026-03-20T00:00:00+00:00",
                "expires_at": "2099-04-20T00:00:00+00:00",
                "source_occurred_at": "2026-03-20T00:00:00+00:00",
                "management_channel": "apple",
                "updated_at": "2026-03-20T00:00:01+00:00",
            }
        ]
        self.addCleanup(setattr, self.repo, "list_subscriptions_for_user", original_list)

        result = module._apply_projection(
            {
                "event_id": "apple:event-2",
                "provider": "apple",
                "user_id": "user-1",
                "occurred_at": "2026-03-25T00:00:00+00:00",
                "created_at": "2026-03-25T00:00:01+00:00",
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "sub-1",
                    "status": "active",
                    "expires_at": "2099-04-25T00:00:00+00:00",
                    "source_occurred_at": "2026-03-25T00:00:00+00:00",
                    "management_channel": "apple",
                    "product_id": "mixroom_starter_monthly",
                    "product_code": "starter_monthly",
                    "plan_code": "starter",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["expires_at"], "2099-04-25T00:00:00+00:00")
        self.assertEqual(entitlement["source_occurred_at"], "2026-03-25T00:00:00+00:00")

    def test_stale_event_is_ignored(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-new",
                "capabilities": {"all_plugins": True},
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
                    "plan_code": "free",
                    "status": "expired",
                },
            }
        )

        self.assertEqual(result, "projected_subscription_only")
        self.assertEqual(self.repo.subscriptions["sub-old"]["status"], "expired")
        self.assertEqual(self.repo.get_entitlement("user-1")["revision"], 7)
        self.assertEqual(self.eventbridge.entries, [])

    def test_studio_subscription_can_replace_personal_entitlement(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "studio-sub",
                "user_id": "user-1",
                "provider": "apple",
                "plan_code": "studio",
                "status": "grace_period",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2099-04-25T00:00:00+00:00",
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
                    "plan_code": "producer",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "studio")
        self.assertEqual(entitlement["status"], "grace_period")
        self.assertEqual(entitlement["source_subscription_id"], "studio-sub")

    def test_expired_higher_plan_does_not_beat_current_lower_plan(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "old-producer",
                "user_id": "user-1",
                "provider": "google",
                "plan_code": "producer",
                "status": "active",
                "effective_at": "2026-03-01T00:00:00+00:00",
                "expires_at": "2026-01-01T00:00:00+00:00",
                "source_occurred_at": "2026-03-21T00:00:00+00:00",
                "management_channel": "google",
                "updated_at": "2026-03-21T00:00:00+00:00",
            }
        )

        result = module._apply_projection(
            {
                "event_id": "google:event-starter",
                "provider": "google",
                "user_id": "user-1",
                "occurred_at": "2026-03-22T00:00:00+00:00",
                "created_at": "2026-03-22T00:00:01+00:00",
                "normalized": {
                    "provider": "google",
                    "subscription_id": "current-starter",
                    "plan_code": "starter",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-22T00:00:00+00:00",
                    "management_channel": "google",
                    "product_id": "mixroom_starter_monthly",
                    "product_code": "starter_monthly",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "starter")
        self.assertEqual(entitlement["source_subscription_id"], "current-starter")

    def test_past_expiry_active_status_projects_as_expired(self):
        result = module._apply_projection(
            {
                "event_id": "google:event-expired-starter",
                "provider": "google",
                "user_id": "user-1",
                "occurred_at": "2026-03-22T00:00:00+00:00",
                "created_at": "2026-03-22T00:00:01+00:00",
                "normalized": {
                    "provider": "google",
                    "subscription_id": "expired-starter",
                    "plan_code": "starter",
                    "status": "active",
                    "expires_at": "2026-01-01T00:00:00+00:00",
                    "source_occurred_at": "2026-03-22T00:00:00+00:00",
                    "management_channel": "google",
                    "product_id": "mixroom_starter_monthly",
                    "product_code": "starter_monthly",
                },
            }
        )

        self.assertEqual(result, "projected")
        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "starter")
        self.assertEqual(entitlement["status"], "expired")
        self.assertFalse(entitlement["capabilities"]["all_plugins"])

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
                    "plan_code": "producer",
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

    def test_handler_skips_already_processed_event_replay(self):
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
                    "plan_code": "producer",
                    "status": "active",
                },
            }
        )
        module.handler({"Records": [{"body": json.dumps({"event_id": "apple:event-1"})}]}, object())
        first_revision = self.repo.get_entitlement("user-1")["revision"]
        first_event_count = len(self.eventbridge.entries)

        module.handler({"Records": [{"body": json.dumps({"event_id": "apple:event-1"})}]}, object())

        self.assertEqual(self.repo.get_entitlement("user-1")["revision"], first_revision)
        self.assertEqual(len(self.eventbridge.entries), first_event_count)


if __name__ == "__main__":
    unittest.main()
