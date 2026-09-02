import base64
import importlib
import json
import unittest
from unittest import mock

from support import FakeBillingRepo

module = importlib.import_module("src.common.google_play")


class GooglePlayTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()

    def test_verify_google_purchase_normalizes_active_subscription(self):
        with mock.patch.object(
            module,
            "_fetch_subscription_purchase",
            return_value={
                "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                "startTime": "2026-03-20T00:00:00+00:00",
                "latestOrderId": "order-1",
                "externalAccountIdentifiers": {
                    "obfuscatedExternalAccountId": "user-1",
                },
                "lineItems": [
                    {
                        "productId": "mixroom_producer_monthly",
                        "expiryTime": "2099-04-20T00:00:00+00:00",
                        "basePlanId": "monthly",
                        "offerId": "launch",
                    }
                ],
            },
        ):
            result = module.verify_google_purchase(
                self.repo,
                purchase_token="purchase-token",
                package_name="ai.mixroom.test",
                expected_user_id="user-1",
            )

        normalized = result["normalized"]
        self.assertEqual(normalized["status"], "active")
        self.assertEqual(normalized["subscription_id"], "order-1")
        self.assertEqual(normalized["base_plan_id"], "monthly")
        self.assertEqual(
            self.repo.get_purchase_token("google", "purchase-token")["user_id"],
            "user-1",
        )

    def test_verify_google_purchase_rejects_cross_account_link(self):
        with mock.patch.object(
            module,
            "_fetch_subscription_purchase",
            return_value={
                "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                "externalAccountIdentifiers": {
                    "obfuscatedExternalAccountId": "other-user",
                },
                "lineItems": [
                    {
                        "productId": "mixroom_producer_monthly",
                        "expiryTime": "2099-04-20T00:00:00+00:00",
                    }
                ],
            },
        ):
            with self.assertRaises(module.ProviderVerificationError) as ctx:
                module.verify_google_purchase(
                    self.repo,
                    purchase_token="purchase-token",
                    package_name="ai.mixroom.test",
                    expected_user_id="user-1",
                )

        self.assertEqual(ctx.exception.status_code, 409)

    def test_verify_google_purchase_resolves_user_from_linked_purchase_token(self):
        self.repo.put_purchase_token(
            "google",
            "old-token",
            {
                "user_id": "user-1",
                "subscription_id": "old-order",
                "product_id": "mixroom_starter_monthly",
            },
        )
        with mock.patch.object(
            module,
            "_fetch_subscription_purchase",
            return_value={
                "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                "startTime": "2026-03-20T00:00:00+00:00",
                "latestOrderId": "new-order",
                "linkedPurchaseToken": "old-token",
                "lineItems": [
                    {
                        "productId": "mixroom_producer_monthly",
                        "expiryTime": "2099-04-20T00:00:00+00:00",
                    }
                ],
            },
        ):
            result = module.verify_google_purchase(
                self.repo,
                purchase_token="new-token",
                package_name="ai.mixroom.test",
            )

        self.assertEqual(result["user_id"], "user-1")
        self.assertEqual(
            self.repo.get_purchase_token("google", "new-token")["user_id"],
            "user-1",
        )

    def test_verify_google_purchase_reclaims_expired_linked_purchase_token(self):
        self.repo.put_purchase_token(
            "google",
            "old-token",
            {
                "user_id": "old-user",
                "subscription_id": "old-order",
                "product_id": "mixroom_starter_monthly",
            },
        )
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "starter",
                "status": "expired",
                "source_provider": "google",
                "source_subscription_id": "old-order",
                "capabilities": {},
                "management_channel": "google",
                "revision": 2,
            }
        )
        self.repo.upsert_subscription(
            {
                "subscription_id": "old-order",
                "user_id": "old-user",
                "provider": "google",
                "plan_code": "starter",
                "status": "expired",
                "expires_at": "2026-01-01T00:00:00+00:00",
            }
        )
        with mock.patch.object(
            module,
            "_fetch_subscription_purchase",
            return_value={
                "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                "startTime": "2026-03-20T00:00:00+00:00",
                "latestOrderId": "new-order",
                "linkedPurchaseToken": "old-token",
                "externalAccountIdentifiers": {
                    "obfuscatedExternalAccountId": "new-user",
                },
                "lineItems": [
                    {
                        "productId": "mixroom_producer_monthly",
                        "expiryTime": "2099-04-20T00:00:00+00:00",
                    }
                ],
            },
        ):
            result = module.verify_google_purchase(
                self.repo,
                purchase_token="new-token",
                package_name="ai.mixroom.test",
                expected_user_id="new-user",
            )

        self.assertEqual(result["user_id"], "new-user")
        self.assertEqual(result["normalized"]["reclaimed_from_user_id"], "old-user")
        self.assertEqual(
            self.repo.get_purchase_token("google", "new-token")["user_id"],
            "new-user",
        )

    def test_verify_google_purchase_blocks_reclaim_when_old_link_has_access(self):
        self.repo.put_purchase_token(
            "google",
            "old-token",
            {
                "user_id": "old-user",
                "subscription_id": "old-order",
                "product_id": "mixroom_starter_monthly",
            },
        )
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "starter",
                "status": "active",
                "expires_at": "2099-04-20T00:00:00+00:00",
                "source_provider": "google",
                "source_subscription_id": "old-order",
                "capabilities": {},
                "management_channel": "google",
                "revision": 2,
            }
        )
        with mock.patch.object(
            module,
            "_fetch_subscription_purchase",
            return_value={
                "subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                "latestOrderId": "new-order",
                "linkedPurchaseToken": "old-token",
                "externalAccountIdentifiers": {
                    "obfuscatedExternalAccountId": "new-user",
                },
                "lineItems": [
                    {
                        "productId": "mixroom_producer_monthly",
                        "expiryTime": "2099-04-20T00:00:00+00:00",
                    }
                ],
            },
        ):
            with self.assertRaises(module.ProviderVerificationError) as ctx:
                module.verify_google_purchase(
                    self.repo,
                    purchase_token="new-token",
                    package_name="ai.mixroom.test",
                    expected_user_id="new-user",
                )

        self.assertEqual(ctx.exception.status_code, 409)

    def test_parse_google_rtdn_body_decodes_pubsub_payload(self):
        encoded = base64.urlsafe_b64encode(
            json.dumps({"packageName": "ai.mixroom.test"}).encode("utf-8")
        ).decode("utf-8")

        payload = module.parse_google_rtdn_body(
            json.dumps({"message": {"data": encoded, "messageId": "msg-1"}})
        )

        self.assertEqual(payload["packageName"], "ai.mixroom.test")
        self.assertEqual(payload["_pubsub_message_id"], "msg-1")

    def test_build_google_webhook_event_for_subscription_notification(self):
        with mock.patch.object(
            module,
            "verify_google_purchase",
            return_value={
                "provider_event_id": "google:sub-1",
                "user_id": "user-1",
                "provider_payload": {"state": "ACTIVE"},
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "plan_code": "producer",
                    "status": "active",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                },
            },
        ):
            result = module.build_google_webhook_event(
                self.repo,
                {
                    "_pubsub_message_id": "msg-1",
                    "packageName": "ai.mixroom.test",
                    "eventTimeMillis": "2026-03-21T00:00:00+00:00",
                    "subscriptionNotification": {
                        "notificationType": 4,
                        "purchaseToken": "purchase-token",
                    },
                },
            )

        self.assertEqual(result["provider_event_id"], "msg-1")
        self.assertEqual(
            result["provider_payload"]["subscriptionNotification"]["notificationType"],
            4,
        )
        self.assertEqual(result["normalized"]["source_occurred_at"], "2026-03-21T00:00:00+00:00")

    def test_build_google_webhook_event_for_voided_purchase(self):
        self.repo.put_purchase_token(
            "google",
            "purchase-token",
            {
                "user_id": "user-1",
                "subscription_id": "sub-1",
                "product_id": "mixroom_producer_monthly",
                "package_name": "ai.mixroom.test",
            },
        )

        result = module.build_google_webhook_event(
            self.repo,
            {
                "_pubsub_message_id": "msg-2",
                "eventTimeMillis": "2026-03-21T00:00:00+00:00",
                "voidedPurchaseNotification": {
                    "purchaseToken": "purchase-token",
                    "refundType": "1",
                },
            },
        )

        self.assertEqual(result["provider_event_id"], "msg-2")
        self.assertEqual(result["normalized"]["status"], "refunded")
        self.assertEqual(result["user_id"], "user-1")

    def test_select_line_item_prefers_active_future_expiry(self):
        result = module._select_line_item(
            {
                "lineItems": [
                    {
                        "productId": "old",
                        "expiryTime": "2000-01-01T00:00:00+00:00",
                    },
                    {
                        "productId": "new",
                        "expiryTime": "2099-01-01T00:00:00+00:00",
                    },
                ]
            }
        )

        self.assertEqual(result["productId"], "new")


if __name__ == "__main__":
    unittest.main()
