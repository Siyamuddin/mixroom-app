import unittest

import support  # noqa: F401
from src.common.events import normalize_webhook


class EventsNormalizationTests(unittest.TestCase):
    def test_web_checkout_provider_webhook_preserves_plan_metadata(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "id": "sub-1",
                "status": "active",
                "metadata": {
                    "mixroom_user_id": "user-1",
                    "plan_code": "starter",
                    "product_code": "starter_monthly",
                    "provider_product_id": "mixroom_starter_monthly",
                },
            },
        )

        self.assertEqual(normalized["plan_code"], "starter")
        self.assertEqual(normalized["product_code"], "starter_monthly")
        self.assertEqual(normalized["product_id"], "mixroom_starter_monthly")

    def test_webhook_maps_legacy_pro_tier_to_producer_plan(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "id": "sub-1",
                "status": "active",
                "metadata": {
                    "mixroom_user_id": "user-1",
                    "tier": "pro",
                    "provider_product_id": "mixroom_pro_monthly",
                },
            },
        )

        self.assertEqual(normalized["plan_code"], "producer")

    def test_paddle_billing_payload_maps_studio_addons(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "event_type": "subscription.updated",
                "occurred_at": "2026-05-18T00:00:00Z",
                "data": {
                    "id": "sub_123",
                    "status": "active",
                    "next_billed_at": "2026-06-18T00:00:00Z",
                    "custom_data": {"plan_key": "studio"},
                    "items": [
                        {
                            "quantity": 1,
                            "price": {
                                "product": {
                                    "id": "pro_studio",
                                    "custom_data": {
                                        "plan_key": "studio",
                                        "product_code": "studio_monthly",
                                    },
                                }
                            },
                        },
                        {
                            "quantity": 2,
                            "price": {
                                "product": {
                                    "custom_data": {
                                        "plan_key": "studio_seat_addon",
                                    },
                                }
                            },
                        },
                        {
                            "quantity": 1,
                            "price": {
                                "product": {
                                    "custom_data": {
                                        "plan_key": "storage_1tb_addon",
                                    },
                                }
                            },
                        },
                    ],
                },
            },
        )

        self.assertEqual(normalized["subscription_id"], "sub_123")
        self.assertEqual(normalized["plan_code"], "studio")
        self.assertEqual(normalized["product_code"], "studio_monthly")
        self.assertEqual(normalized["status"], "active")
        self.assertEqual(normalized["next_billed_at"], "2026-06-18T00:00:00Z")
        self.assertEqual(normalized["seat_count"], 7)
        self.assertEqual(normalized["extra_storage_tb"], 1)

    def test_paddle_item_product_custom_data_maps_starter(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "event_type": "subscription.activated",
                "occurred_at": "2026-05-20T19:58:05Z",
                "data": {
                    "id": "sub_123",
                    "status": "active",
                    "customer_id": "ctm_123",
                    "next_billed_at": "2026-06-20T19:58:04Z",
                    "items": [
                        {
                            "quantity": 1,
                            "product": {
                                "id": "pro_starter",
                                "custom_data": {"plan_key": "starter"},
                            },
                            "price": {
                                "id": "pri_starter_monthly",
                                "product_id": "pro_starter",
                            },
                        },
                    ],
                },
            },
        )

        self.assertEqual(normalized["plan_code"], "starter")
        self.assertEqual(normalized["product_code"], "starter_monthly")
        self.assertEqual(normalized["product_id"], "pro_starter")

    def test_paddle_cancel_at_period_end_keeps_active_until_scheduled_date(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "event_type": "subscription.updated",
                "occurred_at": "2026-05-18T00:00:00Z",
                "data": {
                    "id": "sub_123",
                    "status": "active",
                    "next_billed_at": None,
                    "scheduled_change": {
                        "action": "cancel",
                        "effective_at": "2026-06-18T00:00:00Z",
                    },
                    "custom_data": {"plan_key": "producer"},
                },
            },
        )

        self.assertEqual(normalized["status"], "active")
        self.assertTrue(normalized["cancel_at_period_end"])
        self.assertEqual(normalized["expires_at"], "2026-06-18T00:00:00Z")

    def test_toss_payment_status_payload_maps_payment_and_metadata(self):
        normalized = normalize_webhook(
            "toss",
            {
                "eventType": "PAYMENT_STATUS_CHANGED",
                "createdAt": "2026-05-18T00:00:00Z",
                "data": {
                    "paymentKey": "pay_123",
                    "orderId": "studio_monthly_user_1",
                    "status": "DONE",
                    "totalAmount": 149000,
                    "customerKey": "user-1",
                    "metadata": {
                        "plan_key": "studio",
                        "product_code": "studio_monthly",
                    },
                },
            },
        )

        self.assertEqual(normalized["provider"], "toss")
        self.assertEqual(normalized["subscription_id"], "pay_123")
        self.assertEqual(normalized["customer_id"], "user-1")
        self.assertEqual(normalized["status"], "active")
        self.assertEqual(normalized["plan_code"], "studio")
        self.assertEqual(normalized["product_code"], "studio_monthly")
        self.assertEqual(normalized["product_id"], "studio_monthly_user_1")

    def test_toss_billing_metadata_can_provide_stable_subscription_id(self):
        normalized = normalize_webhook(
            "toss",
            {
                "eventType": "BILLING_PAYMENT_APPROVED",
                "data": {
                    "paymentKey": "pay_123",
                    "orderId": "order_1",
                    "status": "DONE",
                    "customerKey": "customer-1",
                    "metadata": {
                        "subscription_id": "toss-billing:customer-1:studio_monthly",
                        "product_code": "studio_monthly",
                        "plan_code": "studio",
                        "seat_count": 8,
                        "extra_storage_tb": 2,
                    },
                },
            },
        )

        self.assertEqual(
            normalized["subscription_id"],
            "toss-billing:customer-1:studio_monthly",
        )
        self.assertEqual(normalized["seat_count"], 8)
        self.assertEqual(normalized["extra_storage_tb"], 2)


if __name__ == "__main__":
    unittest.main()
