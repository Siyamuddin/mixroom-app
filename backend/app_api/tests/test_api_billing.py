import importlib
import json
import unittest
from unittest import mock

from support import FakeBillingRepo, decode_json_response
from src.common.billing_catalog import default_catalog

module = importlib.import_module("src.handlers.api_billing")


class ApiBillingTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.original_repo = module.repo
        self.original_catalog_repo = module.catalog_repo
        self.original_collaboration_repo = module.collaboration_repo
        self.original_extract_user_id = module.extract_user_id_from_event
        self.original_capture_event = module.capture_event
        self.original_verify_apple_purchase = module.verify_apple_purchase
        self.original_verify_google_purchase = module.verify_google_purchase
        self.original_build_management_links = module.build_management_links
        self.original_confirm_toss_payment = module.confirm_toss_payment
        self.original_issue_toss_billing_key = module.issue_toss_billing_key
        self.original_charge_toss_billing_key = module.charge_toss_billing_key
        self.original_delete_toss_billing_key = module.delete_toss_billing_key
        self.original_put_secure_parameter_string = module.put_secure_parameter_string
        self.original_load_provider_api_key = module.load_provider_api_key
        module.repo = self.repo
        module.catalog_repo = mock.Mock()
        module.catalog_repo.get_catalog.return_value = default_catalog()
        module.catalog_repo.get_product.return_value = {}
        module.collaboration_repo = mock.Mock()
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [],
            "summary": {},
        }
        module.extract_user_id_from_event = lambda event: "user-1"
        module.capture_event = mock.Mock()

    def tearDown(self):
        module.repo = self.original_repo
        module.catalog_repo = self.original_catalog_repo
        module.collaboration_repo = self.original_collaboration_repo
        module.extract_user_id_from_event = self.original_extract_user_id
        module.capture_event = self.original_capture_event
        module.verify_apple_purchase = self.original_verify_apple_purchase
        module.verify_google_purchase = self.original_verify_google_purchase
        module.build_management_links = self.original_build_management_links
        module.confirm_toss_payment = self.original_confirm_toss_payment
        module.issue_toss_billing_key = self.original_issue_toss_billing_key
        module.charge_toss_billing_key = self.original_charge_toss_billing_key
        module.delete_toss_billing_key = self.original_delete_toss_billing_key
        module.put_secure_parameter_string = self.original_put_secure_parameter_string
        module.load_provider_api_key = self.original_load_provider_api_key

    def seed_toss_one_time_checkout_order(
        self,
        *,
        order_id="order-1",
        amount=149000,
        product_code="studio_monthly",
        plan_code="studio",
        customer_key="customer-1",
        user_id="user-1",
        seat_count=None,
        extra_storage_tb=0,
    ):
        self.repo.put_billing_event_if_new(
            {
                "event_id": f"toss:checkout-order-{order_id}",
                "event_type": "checkout_session_created",
                "provider": "toss",
                "provider_event_id": f"checkout-order-{order_id}",
                "user_id": user_id,
                "raw_payload": {
                    "provider": "toss",
                    "product_code": product_code,
                    "plan_code": plan_code,
                    "toss": {
                        "flow": "payment",
                        "amount": amount,
                        "currency": "KRW",
                        "order_id": order_id,
                        "customer_key": customer_key,
                        "seat_count": seat_count,
                        "extra_storage_tb": extra_storage_tb,
                    },
                },
                "normalized": {
                    "provider": "toss",
                    "product_code": product_code,
                    "plan_code": plan_code,
                    "order_id": order_id,
                    "amount": amount,
                    "currency": "KRW",
                },
            }
        )
        return {
            "order_id": order_id,
            "amount": amount,
            "customer_key": customer_key,
        }

    def test_checkout_session_uses_toss_for_kr(self):
        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"region_code": "KR"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertEqual(payload["checkout_url"], "https://www.mixroom.ai/#pricing")
        self.assertEqual(self.repo.queued_projection_ids, [])
        event = next(iter(self.repo.billing_events.values()))
        self.assertEqual(event["event_type"], "checkout_session_created")

    def test_checkout_session_persists_toss_billing_order(self):
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "region_code": "KR",
                        "product_code": "studio_monthly",
                        "additional_seats": 2,
                        "extra_storage_tb": 1,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertEqual(payload["toss"]["flow"], "billing")
        self.assertEqual(payload["toss"]["amount"], 208000)
        self.assertEqual(payload["toss"]["seat_count"], 7)
        order_id = payload["toss"]["order_id"]
        event = self.repo.get_billing_event(f"toss:checkout-order-{order_id}")
        self.assertIsNotNone(event)
        self.assertEqual(event["user_id"], "user-1")
        self.assertEqual(event["raw_payload"]["product_code"], "studio_monthly")

    def test_checkout_session_rejects_unconfigured_paddle_yearly_price(self):
        module.catalog_repo.get_product.return_value = {
            "code": "producer_yearly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "yearly",
            "label": "Producer Yearly",
            "enabled": True,
            "price_krw": 299000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "region_code": "KR",
                        "product_code": "producer_yearly",
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("Paddle price is not configured", decode_json_response(response)["error"])

    def test_checkout_session_rejects_unconfigured_paddle_yearly_studio_price(self):
        module.catalog_repo.get_product.return_value = {
            "code": "studio_yearly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "yearly",
            "label": "Studio Yearly",
            "enabled": True,
            "price_krw": 1490000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "region_code": "US",
                        "product_code": "studio_yearly",
                        "additional_seats": 2,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("Paddle price is not configured", decode_json_response(response)["error"])

    def test_checkout_session_rejects_contract_products(self):
        module.catalog_repo.get_product.return_value = {
            "code": "enterprise_contract",
            "type": "contract",
            "plan_code": "enterprise",
            "enabled": True,
            "management_channel": "admin",
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"product_code": "enterprise_contract"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("sales@mixroom.ai", response["body"])
        self.assertEqual(self.repo.billing_events, {})

    def test_checkout_session_rejects_conflicting_active_subscription(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2099-04-20T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "apple-sub-1",
                "capabilities": {},
                "management_channel": "apple",
                "revision": 2,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"region_code": "US"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("already have an active subscription", response["body"])
        self.assertEqual(self.repo.billing_events, {})

    def test_checkout_session_rejects_team_plan_with_active_personal_subscription(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2099-04-20T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "apple-sub-1",
                "capabilities": {},
                "management_channel": "apple",
                "revision": 2,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "type": "subscription",
            "plan_code": "studio",
            "enabled": True,
            "management_channel": "web",
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {"region_code": "US", "product_code": "studio_monthly"}
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("already have an active subscription", response["body"])
        self.assertEqual(self.repo.billing_events, {})

    def test_checkout_session_allows_team_plan_with_non_billing_entitlement(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "free",
                "status": "active",
                "source_provider": "admin_grant",
                "capabilities": {},
                "management_channel": "free",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "type": "subscription",
            "plan_code": "studio",
            "enabled": True,
            "management_channel": "web",
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {"region_code": "US", "product_code": "studio_monthly"}
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["product"]["plan_code"], "studio")
        self.assertEqual(len(self.repo.billing_events), 1)

    def test_checkout_session_rejects_active_owned_subscription_even_when_entitlement_is_admin_grant(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-active",
                "user_id": "user-1",
                "provider": "paddle",
                "plan_code": "studio",
                "status": "active",
                "product_code": "studio_monthly",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "education",
                "status": "active",
                "source_provider": "admin_grant",
                "capabilities": {},
                "management_channel": "admin",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "type": "subscription",
            "plan_code": "studio",
            "enabled": True,
            "management_channel": "web",
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {"region_code": "KR", "product_code": "studio_monthly"}
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("already have an active subscription", response["body"])
        self.assertEqual(self.repo.billing_events, {})

    def test_mobile_verify_google_persists_event_and_tracks_analytics(self):
        module.verify_google_purchase = mock.Mock(
            return_value={
                "provider_event_id": "google:event-1",
                "user_id": "user-1",
                "provider_payload": {"state": "ACTIVE"},
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "status": "active",
                    "product_id": "mixroom_producer_monthly",
                    "product_code": "producer_monthly",
                    "plan_code": "producer",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "google",
                },
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/mobile/google/verify",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "purchase_token": "purchase-token",
                        "product_id": "mixroom_producer_monthly",
                        "price": 9.99,
                        "currency_code": "USD",
                        "client_context": {"distinct_id": "device-1"},
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["normalized"]["subscription_id"], "sub-1")
        self.assertEqual(payload["normalized"]["plan_code"], "producer")
        module.capture_event.assert_called_once()
        tracked_args = module.capture_event.call_args.args
        tracked_kwargs = module.capture_event.call_args.kwargs
        self.assertEqual(tracked_args[0], "subscription_started")
        self.assertEqual(tracked_kwargs["distinct_id"], "device-1")
        self.assertEqual(tracked_kwargs["properties"]["billing_cycle"], "monthly")
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])

    def test_toss_confirm_confirms_payment_and_enqueues_projection(self):
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }
        order = self.seed_toss_one_time_checkout_order(
            order_id="order-1",
            amount=149000,
            product_code="studio_monthly",
            plan_code="studio",
            customer_key="customer-1",
        )
        module.confirm_toss_payment = mock.Mock(
            return_value={
                "paymentKey": "pay-1",
                "orderId": order["order_id"],
                "status": "DONE",
                "totalAmount": 149000,
                "customerKey": order["customer_key"],
                "metadata": {
                    "mixroom_user_id": "attacker",
                    "plan_code": "starter",
                    "product_code": "starter_monthly",
                },
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-1",
                        "order_id": order["order_id"],
                        "amount": 149000,
                        "product_code": "starter_monthly",
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["provider"], "toss")
        self.assertEqual(payload["normalized"]["plan_code"], "studio")
        self.assertEqual(payload["normalized"]["product_code"], "studio_monthly")
        self.assertEqual(payload["normalized"]["customer_id"], order["customer_key"])
        self.assertNotIn("payment", payload)
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])
        module.confirm_toss_payment.assert_called_once_with("pay-1", order["order_id"], 149000)

    def test_toss_confirm_rejects_account_checkout_order_without_auth(self):
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }
        checkout = module.handler(
            {
                "rawPath": "/v1/billing/web/checkout-session",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "region_code": "KR",
                        "product_code": "studio_monthly",
                        "additional_seats": 2,
                        "extra_storage_tb": 1,
                    }
                ),
            },
            object(),
        )
        order = decode_json_response(checkout)["toss"]
        module.extract_user_id_from_event = lambda event: ""
        module.confirm_toss_payment = mock.Mock(
            return_value={
                "paymentKey": "pay-widget-1",
                "orderId": order["order_id"],
                "status": "DONE",
                "totalAmount": 208000,
                "approvedAt": "2026-05-21T00:00:00+00:00",
                "customerKey": order["customer_key"],
                "method": "card",
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-widget-1",
                        "order_id": order["order_id"],
                        "amount": 208000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 403)
        payload = decode_json_response(response)
        self.assertIn("not eligible", payload["error"])
        module.confirm_toss_payment.assert_not_called()

    def test_toss_confirm_allows_fixed_anonymous_one_time_payment_without_subscription(self):
        module.extract_user_id_from_event = lambda event: ""
        module.confirm_toss_payment = mock.Mock(
            return_value={
                "paymentKey": "pay-galhyeon-1",
                "orderId": "galhyeon-material-1760000000000-abc123",
                "orderName": "갈현 재료비",
                "status": "DONE",
                "totalAmount": 1589000,
                "method": "카드",
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-galhyeon-1",
                        "order_id": "galhyeon-material-1760000000000-abc123",
                        "amount": 1589000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["product_code"], "galhyeon-material")
        self.assertEqual(payload["amount"], 1589000)
        self.assertEqual(self.repo.queued_projection_ids, [])
        self.assertEqual(self.repo.subscriptions, {})
        event = self.repo.get_billing_event("toss:confirm-pay-galhyeon-1")
        self.assertEqual(event["event_type"], "toss_anonymous_one_time_payment_confirmed")
        self.assertEqual(event["user_id"], "")
        self.assertEqual(event["normalized"], {})
        self.assertEqual(event["processing_result"], "not_applicable_one_time_payment")
        module.confirm_toss_payment.assert_called_once_with(
            "pay-galhyeon-1",
            "galhyeon-material-1760000000000-abc123",
            1589000,
        )

    def test_public_payment_link_exposes_independent_items(self):
        module.catalog_repo.get_one_time_product.return_value = {
            "code": "workshop",
            "page_title": "워크숍 결제",
            "order_name": "워크숍 결제",
            "amount": 120000,
            "enabled": True,
            "items": [
                {"code": "materials", "order_name": "재료비", "amount": 120000, "currency": "KRW"},
                {"code": "tuition", "order_name": "수강료", "amount": 80000, "currency": "KRW"},
            ],
        }

        response = module.handler(
            {"rawPath": "/v1/billing/public/one-time-products/workshop", "requestContext": {"http": {"method": "GET"}}},
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["page_title"], "워크숍 결제")
        self.assertEqual([item["code"] for item in payload["items"]], ["materials", "tuition"])
        module.catalog_repo.get_one_time_product.assert_called_once_with("workshop", public_only=True)

    def test_public_payment_link_creates_and_confirms_selected_item_only(self):
        intent = {
            "order_id": "one-workshop-materials-123",
            "page_code": "workshop",
            "item_code": "materials",
            "product_code": "workshop-materials",
            "order_name": "재료비",
            "amount": 120000,
            "currency": "KRW",
        }
        module.catalog_repo.create_one_time_checkout_intent.return_value = intent

        create = module.handler(
            {
                "rawPath": "/v1/billing/public/toss/checkout-intents",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"code": "workshop", "item_code": "materials"}),
            }, object(),
        )
        self.assertEqual(create["statusCode"], 201)
        self.assertEqual(decode_json_response(create)["amount"], 120000)
        module.catalog_repo.create_one_time_checkout_intent.assert_called_once_with("workshop", "materials")

        module.catalog_repo.get_one_time_checkout_intent.return_value = intent
        module.confirm_toss_payment = mock.Mock(return_value={
            "paymentKey": "pay-materials", "orderId": intent["order_id"], "orderName": "재료비",
            "status": "DONE", "totalAmount": 120000, "method": "카드",
        })
        confirm = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"payment_key": "pay-materials", "order_id": intent["order_id"], "amount": 120000}),
            }, object(),
        )
        self.assertEqual(confirm["statusCode"], 200)
        self.assertEqual(decode_json_response(confirm)["product_code"], "workshop-materials")
        self.assertEqual(self.repo.queued_projection_ids, [])
        module.confirm_toss_payment.assert_called_once_with("pay-materials", intent["order_id"], 120000)

    def test_toss_confirm_rejects_anonymous_one_time_wrong_amount_before_toss(self):
        module.extract_user_id_from_event = lambda event: ""
        module.confirm_toss_payment = mock.Mock()

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-galhyeon-1",
                        "order_id": "galhyeon-instructor-1760000000000-abc123",
                        "amount": 1589000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("amount mismatch", response["body"])
        module.confirm_toss_payment.assert_not_called()

    def test_toss_confirm_allows_testgal_anonymous_one_time_payment(self):
        module.confirm_toss_payment = mock.Mock(
            return_value={
                "paymentKey": "pay-testgal-1",
                "orderId": "testgal-1000-1760000000000-abc123",
                "orderName": "결제 테스트",
                "status": "DONE",
                "totalAmount": 1000,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-testgal-1",
                        "order_id": "testgal-1000-1760000000000-abc123",
                        "amount": 1000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["product_code"], "testgal-1000")
        self.assertEqual(payload["amount"], 1000)
        self.assertEqual(self.repo.queued_projection_ids, [])
        self.assertEqual(self.repo.subscriptions, {})

    def test_toss_confirm_routes_testgal_to_one_time_flow_when_visitor_is_logged_in(self):
        module.confirm_toss_payment = mock.Mock(
            return_value={
                "paymentKey": "pay-testgal-signed-in",
                "orderId": "testgal-1000-1760000000000-def456",
                "orderName": "결제 테스트",
                "status": "DONE",
                "totalAmount": 1000,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-testgal-signed-in",
                        "order_id": "testgal-1000-1760000000000-def456",
                        "amount": 1000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.repo.queued_projection_ids, [])
        self.assertEqual(self.repo.subscriptions, {})

    def test_toss_same_plan_legacy_one_time_renewal_starts_billing_checkout(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-payment:old-order",
                "user_id": "user-1",
                "provider": "toss",
                "status": "active",
                "plan_code": "starter",
                "product_code": "starter_monthly",
                "expires_at": "2026-06-21T00:00:00+00:00",
                "billing_amount": 6600,
                "billing_currency": "KRW",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "toss",
                "source_subscription_id": "toss-payment:old-order",
                "plan_code": "starter",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "starter_monthly",
            "plan_code": "starter",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Starter Monthly",
            "enabled": True,
            "price_krw": 6600,
        }

        checkout = module.handler(
            {
                "rawPath": "/v1/billing/web/subscription/change",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"product_code": "starter_monthly"}),
            },
            object(),
        )
        self.assertEqual(checkout["statusCode"], 200)
        payload = decode_json_response(checkout)
        self.assertEqual(payload["provider"], "toss")
        self.assertTrue(payload["checkout_required"])
        self.assertEqual(payload["checkout_flow"], "toss_billing")
        self.assertEqual(payload["effective"], "after_payment_method_setup")
        self.assertEqual(payload["toss"]["flow"], "billing")
        self.assertEqual(payload["toss"]["amount"], 6600)

    def test_toss_confirm_duplicate_returns_409_without_reconfirming(self):
        self.repo.put_billing_event_if_new(
            {
                "event_id": "toss:confirm-pay-1",
                "event_type": "toss_payment_confirmed",
                "provider": "toss",
                "provider_event_id": "confirm-pay-1",
                "user_id": "user-1",
                "normalized": {"subscription_id": "toss-payment:order-1"},
            }
        )
        module.confirm_toss_payment = mock.Mock()

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-1",
                        "order_id": "order-1",
                        "amount": 149000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        payload = decode_json_response(response)
        self.assertTrue(payload["idempotent_replay"])
        module.confirm_toss_payment.assert_not_called()

    def test_toss_confirm_rejects_amount_mismatch(self):
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }
        order = self.seed_toss_one_time_checkout_order(
            order_id="order-1",
            amount=149000,
            product_code="studio_monthly",
            plan_code="studio",
            customer_key="customer-1",
        )
        module.confirm_toss_payment = mock.Mock()

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/confirm",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "payment_key": "pay-1",
                        "order_id": order["order_id"],
                        "amount": 1000,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("amount mismatch", response["body"])
        module.confirm_toss_payment.assert_not_called()
        self.assertEqual(self.repo.queued_projection_ids, [])

    def test_toss_billing_key_issues_stores_charges_and_enqueues_projection(self):
        module.issue_toss_billing_key = mock.Mock(
            return_value={
                "billingKey": "billing-key-1",
                "card": {"company": "Shinhan", "number": "123456******7890"},
            }
        )
        module.charge_toss_billing_key = mock.Mock(
            return_value={
                "paymentKey": "pay-billing-1",
                "orderId": "order-1",
                "status": "DONE",
                "totalAmount": 208000,
                "approvedAt": "2026-05-19T00:00:00+00:00",
                "customerKey": "customer-1",
            }
        )
        module.put_secure_parameter_string = mock.Mock(return_value="/mixroom/payment-credentials/test/toss/customer-1")
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/billing-key",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "auth_key": "auth-1",
                        "customer_key": "customer-1",
                        "product_code": "studio_monthly",
                        "order_id": "order-1",
                        "additional_seats": 2,
                        "extra_storage_tb": 1,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["normalized"]["plan_code"], "studio")
        self.assertEqual(
            payload["normalized"]["billing_key_parameter_name"],
            "/mixroom/payment-credentials/test/toss/customer-1",
        )
        self.assertEqual(payload["normalized"]["billing_amount"], 208000)
        self.assertEqual(payload["normalized"]["seat_count"], 7)
        self.assertEqual(payload["normalized"]["extra_storage_tb"], 1)
        self.assertEqual(
            self.repo.customer_links["toss:customer-1"]["billing_key_parameter_name"],
            "/mixroom/payment-credentials/test/toss/customer-1",
        )
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])
        module.issue_toss_billing_key.assert_called_once_with("auth-1", "customer-1")
        module.charge_toss_billing_key.assert_called_once()
        self.assertEqual(module.charge_toss_billing_key.call_args.kwargs["amount"], 208000)

    def test_toss_billing_key_duplicate_order_does_not_charge_twice(self):
        module.issue_toss_billing_key = mock.Mock(return_value={"billingKey": "billing-key-1"})
        module.charge_toss_billing_key = mock.Mock(
            return_value={
                "paymentKey": "pay-billing-1",
                "orderId": "order-1",
                "status": "DONE",
                "totalAmount": 149000,
                "approvedAt": "2026-05-19T00:00:00+00:00",
                "customerKey": "customer-1",
            }
        )
        module.put_secure_parameter_string = mock.Mock(return_value="/mixroom/payment-credentials/test/toss/customer-1")
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }
        event = {
            "rawPath": "/v1/billing/web/toss/billing-key",
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps(
                {
                    "auth_key": "auth-1",
                    "customer_key": "customer-1",
                    "product_code": "studio_monthly",
                    "order_id": "order-1",
                }
            ),
        }

        first = module.handler(event, object())
        second = module.handler(event, object())

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["statusCode"], 200)
        self.assertTrue(decode_json_response(second)["idempotent_replay"])
        module.charge_toss_billing_key.assert_called_once()

    def test_toss_cancel_marks_subscription_cancel_at_period_end(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "provider": "toss",
                "status": "active",
                "next_billed_at": "2026-06-19T00:00:00+00:00",
                "billing_key_parameter_name": "/mixroom/payment-credentials/test/toss/customer-1",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "toss",
                "source_subscription_id": "sub-1",
                "plan_code": "studio",
                "status": "active",
            }
        )
        module.load_provider_api_key = mock.Mock(return_value="billing-key-1")
        module.delete_toss_billing_key = mock.Mock(return_value={})

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/cancel",
                "requestContext": {"http": {"method": "POST"}},
                "body": "{}",
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertTrue(self.repo.subscriptions["sub-1"]["cancel_at_period_end"])
        self.assertTrue(self.repo.entitlements["user-1"]["cancel_at_period_end"])
        self.assertEqual(self.repo.entitlements["user-1"]["expires_at"], "2026-06-19T00:00:00+00:00")
        module.delete_toss_billing_key.assert_called_once_with("billing-key-1")

    def test_toss_subscription_update_changes_next_renewal_amount_and_addons(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-billing:customer-1:studio_monthly",
                "user_id": "user-1",
                "provider": "toss",
                "status": "active",
                "plan_code": "studio",
                "product_code": "studio_monthly",
                "next_billed_at": "2026-06-19T00:00:00+00:00",
                "billing_amount": 149000,
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "toss",
                "source_subscription_id": "toss-billing:customer-1:studio_monthly",
                "plan_code": "studio",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "studio_monthly",
            "plan_code": "studio",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Studio Monthly",
            "enabled": True,
            "price_krw": 149000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/toss/subscription",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "product_code": "studio_monthly",
                        "additional_seats": 3,
                        "extra_storage_tb": 2,
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["effective"], "next_renewal")
        self.assertEqual(payload["billing_amount"], 245000)
        self.assertEqual(payload["seat_count"], 8)
        self.assertEqual(payload["extra_storage_tb"], 2)
        entitlement = self.repo.entitlements["user-1"]
        self.assertEqual(entitlement["seat_count"], 8)
        self.assertEqual(entitlement["extra_storage_tb"], 2)
        self.assertEqual(entitlement["limit_overrides"]["members"], 8)
        self.assertEqual(entitlement["limit_overrides"]["shared_storage_gb"], 3072)

    def test_web_subscription_change_updates_paddle_subscription(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub_123",
                "user_id": "user-1",
                "provider": "paddle",
                "customer_id": "ctm_123",
                "status": "active",
                "plan_code": "starter",
                "product_code": "starter_monthly",
                "next_billed_at": "2026-06-19T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "paddle",
                "source_subscription_id": "sub_123",
                "plan_code": "starter",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "producer_monthly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Producer Monthly",
            "enabled": True,
        }

        with mock.patch.object(
            module,
            "_paddle_patch_subscription",
            return_value={
                "data": {
                    "id": "sub_123",
                    "status": "active",
                    "next_billed_at": "2026-07-19T00:00:00Z",
                }
            },
        ) as patch_subscription:
            response = module.handler(
                {
                    "rawPath": "/v1/billing/web/subscription/change",
                    "requestContext": {"http": {"method": "POST"}},
                    "body": json.dumps({"product_code": "producer_monthly"}),
                },
                object(),
            )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "paddle")
        self.assertEqual(payload["plan_code"], "producer")
        self.assertEqual(payload["proration_billing_mode"], "prorated_immediately")
        patch_subscription.assert_called_once()
        request_payload = patch_subscription.call_args.args[1]
        self.assertEqual(request_payload["items"][0]["price_id"], "pri_01ks4kfx9v056g4bg90dw5sbgj")
        self.assertEqual(self.repo.subscriptions["sub_123"]["plan_code"], "producer")
        self.assertEqual(self.repo.entitlements["user-1"]["plan_code"], "producer")

    def test_web_subscription_change_preview_quotes_paddle_subscription(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "sub_123",
                "user_id": "user-1",
                "provider": "paddle",
                "customer_id": "ctm_123",
                "status": "active",
                "plan_code": "starter",
                "product_code": "starter_monthly",
                "billing_amount": 500,
                "billing_currency": "USD",
                "next_billed_at": "2026-06-19T00:00:00+00:00",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "paddle",
                "source_subscription_id": "sub_123",
                "plan_code": "starter",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.side_effect = lambda code: {
            "starter_monthly": {
                "code": "starter_monthly",
                "plan_code": "starter",
                "type": "subscription",
                "billing_interval": "monthly",
                "label": "Starter Monthly",
                "enabled": True,
                "price_display": "$5/mo",
            },
            "producer_monthly": {
                "code": "producer_monthly",
                "plan_code": "producer",
                "type": "subscription",
                "billing_interval": "monthly",
                "label": "Producer Monthly",
                "enabled": True,
                "price_display": "$20/mo",
            },
        }.get(code, {})

        with mock.patch.object(
            module,
            "_paddle_preview_subscription",
            return_value={
                "data": {
                    "immediate_transaction": {
                        "currency_code": "USD",
                        "details": {"totals": {"total": "1500"}},
                    },
                    "next_transaction": {
                        "currency_code": "USD",
                        "billed_at": "2026-06-19T00:00:00Z",
                        "details": {"totals": {"total": "2000"}},
                    },
                    "update_summary": {"result": "debit"},
                }
            },
        ) as preview_subscription:
            response = module.handler(
                {
                    "rawPath": "/v1/billing/web/subscription/change/preview",
                    "requestContext": {"http": {"method": "POST"}},
                    "body": json.dumps({"product_code": "producer_monthly"}),
                },
                object(),
            )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertTrue(payload["preview"])
        self.assertEqual(payload["provider"], "paddle")
        self.assertFalse(payload["checkout_required"])
        self.assertEqual(payload["current"]["price_formatted"], "$5.00")
        self.assertEqual(payload["target"]["price_formatted"], "$20.00")
        self.assertEqual(payload["amount_due_now"]["price_formatted"], "$15.00")
        self.assertEqual(payload["next_transaction"]["price_formatted"], "$20.00")
        preview_subscription.assert_called_once()
        self.assertNotEqual(self.repo.subscriptions["sub_123"]["plan_code"], "producer")

    def test_web_subscription_change_migrates_toss_one_time_to_billing_checkout(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-payment:order-1",
                "user_id": "user-1",
                "provider": "toss",
                "status": "active",
                "plan_code": "starter",
                "product_code": "starter_monthly",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "toss",
                "source_subscription_id": "toss-payment:order-1",
                "plan_code": "starter",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "producer_monthly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Producer Monthly",
            "enabled": True,
            "price_krw": 29000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/subscription/change",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"product_code": "producer_monthly"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertTrue(payload["checkout_required"])
        self.assertEqual(payload["checkout_flow"], "toss_billing")
        self.assertEqual(payload["effective"], "after_payment_method_setup")
        self.assertEqual(payload["toss"]["flow"], "billing")
        self.assertEqual(payload["toss"]["amount"], 29000)

    def test_web_subscription_change_preview_quotes_toss_billing_checkout(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-payment:order-1",
                "user_id": "user-1",
                "provider": "toss",
                "status": "active",
                "plan_code": "starter",
                "product_code": "starter_monthly",
                "billing_amount": 6600,
                "billing_currency": "KRW",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "source_provider": "toss",
                "source_subscription_id": "toss-payment:order-1",
                "plan_code": "starter",
                "status": "active",
                "revision": 1,
            }
        )
        module.catalog_repo.get_product.return_value = {
            "code": "producer_monthly",
            "plan_code": "producer",
            "type": "subscription",
            "billing_interval": "monthly",
            "label": "Producer Monthly",
            "enabled": True,
            "price_krw": 29000,
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/web/subscription/change/preview",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"product_code": "producer_monthly"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertTrue(payload["checkout_required"])
        self.assertEqual(payload["checkout_flow"], "toss_billing")
        self.assertEqual(payload["effective"], "after_payment_method_setup")
        self.assertEqual(payload["current"]["price_formatted"], "₩6,600")
        self.assertEqual(payload["target"]["price_formatted"], "₩29,000")
        self.assertEqual(payload["amount_due_now"]["price_formatted"], "₩29,000")
        self.assertEqual(self.repo.subscriptions["toss-payment:order-1"]["plan_code"], "starter")

    def test_duplicate_mobile_verify_returns_accepted_false_without_tracking(self):
        module.verify_apple_purchase = mock.Mock(
            return_value={
                "provider_event_id": "apple:event-1",
                "user_id": "user-1",
                "provider_payload": {"transaction": "ok"},
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "apple-sub-1",
                    "status": "active",
                    "product_id": "mixroom_producer_monthly",
                    "plan_code": "producer",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "apple",
                },
            }
        )

        event = {
            "rawPath": "/v1/billing/mobile/apple/verify",
            "requestContext": {"http": {"method": "POST"}},
            "body": json.dumps({"transaction_jws": "signed.tx.payload"}),
        }

        first = decode_json_response(module.handler(event, object()))
        second = decode_json_response(module.handler(event, object()))

        self.assertTrue(first["accepted"])
        self.assertFalse(second["accepted"])
        module.capture_event.assert_called_once()

    def test_restore_request_enqueues_projection(self):
        response = module.handler(
            {
                "rawPath": "/v1/billing/restore",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"provider": "apple"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "apple")
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])

    def test_portal_url_uses_entitlement_provider(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "producer",
                "status": "active",
                "source_provider": "google",
                "source_subscription_id": "sub-1",
                "capabilities": {},
                "management_channel": "google",
                "revision": 2,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/portal-url",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "google")
        self.assertEqual(payload["label"], "Manage in Play Store")
        self.assertTrue(payload["manage_in_app"])
        self.assertIn("play.google.com", payload["url"])

    def test_portal_url_labels_web_subscriptions_as_web_managed(self):
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "paddle",
                "source_subscription_id": "sub-1",
                "capabilities": {},
                "management_channel": "web",
                "revision": 2,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/portal-url",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["label"], "Manage on web")
        self.assertFalse(payload["manage_in_app"])

    def test_billing_me_returns_safe_management_state(self):
        module.build_management_links = mock.Mock(
            return_value={
                "configured": True,
                "reason": "",
                "links": {
                    "overview": "https://buyer-portal.paddle.com/overview",
                    "update_payment_method": "https://buyer-portal.paddle.com/update-payment-method",
                    "cancel_subscription": "https://buyer-portal.paddle.com/cancel",
                },
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "paddle",
                "source_subscription_id": "sub-1",
                "source_customer_id": "ctm-1",
                "billing_email": "billing@example.com",
                "capabilities": {},
                "management_channel": "web",
                "revision": 2,
                "next_billed_at": "2026-06-18T00:00:00Z",
                "seat_count": 7,
                "extra_storage_tb": 2,
                "payment_method": {
                    "brand": "visa",
                    "last4": "4242",
                    "exp_month": 12,
                    "exp_year": 2029,
                    "ignored": "secret",
                },
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "paddle")
        self.assertEqual(payload["plan"], "studio")
        self.assertEqual(payload["next_billed_at"], "2026-06-18T00:00:00Z")
        self.assertEqual(payload["seat_count"], 7)
        self.assertEqual(payload["extra_storage_tb"], 2)
        self.assertEqual(payload["billing_email"], "billing@example.com")
        self.assertEqual(payload["payment_method"]["brand"], "visa")
        self.assertNotIn("ignored", payload["payment_method"])
        self.assertEqual(payload["provider_ids"]["paddle_customer_id"], "ctm-1")
        self.assertEqual(payload["provider_ids"]["paddle_subscription_id"], "sub-1")
        self.assertEqual(payload["manage"]["label"], "Manage on web")
        self.assertEqual(payload["manage_url"], "https://buyer-portal.paddle.com/overview")
        self.assertEqual(
            payload["update_payment_method_url"],
            "https://buyer-portal.paddle.com/update-payment-method",
        )
        self.assertEqual(payload["provider_management"]["configured"], True)
        module.build_management_links.assert_called_once_with(
            provider="paddle",
            customer_id="ctm-1",
            subscription_id="sub-1",
        )

    def test_billing_me_omits_toss_one_time_management_links(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-payment:order-1",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "studio",
                "status": "active",
                "product_code": "studio_monthly",
                "one_time_checkout_url": "/payment/checkout?order_id=order-1",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "studio",
                "status": "active",
                "source_provider": "toss",
                "source_subscription_id": "toss-payment:order-1",
                "source_customer_id": "customer-1",
                "management_channel": "web",
                "revision": 2,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertEqual(payload["manage_url"], "")
        self.assertEqual(payload["update_payment_method_url"], "")
        self.assertEqual(payload["cancel_subscription_url"], "")
        self.assertEqual(payload["invoices_url"], "")
        self.assertEqual(payload["provider_management"]["reason"], "toss_one_time_payment")
        self.assertEqual(payload["one_time_checkout_url"], "/payment/checkout?order_id=order-1")

    def test_billing_me_reports_toss_recurring_management_configured(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-billing:customer-1:starter_monthly",
                "user_id": "user-1",
                "provider": "toss",
                "customer_id": "customer-1",
                "plan_code": "starter",
                "status": "active",
                "product_code": "starter_monthly",
                "next_billed_at": "2026-06-18T00:00:00Z",
                "billing_key_parameter_name": "/mixroom/payment-credentials/test/toss/customer-1",
                "billing_amount": 6600,
                "billing_currency": "KRW",
            }
        )
        self.repo.put_entitlement(
            {
                "user_id": "user-1",
                "plan_code": "starter",
                "status": "active",
                "source_provider": "toss",
                "source_subscription_id": "toss-billing:customer-1:starter_monthly",
                "source_customer_id": "customer-1",
                "management_channel": "toss",
                "revision": 2,
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "toss")
        self.assertEqual(payload["customer_key"], "customer-1")
        self.assertEqual(payload["provider_management"]["configured"], True)
        self.assertEqual(payload["provider_management"]["reason"], "")

    def test_billing_subscriptions_splits_owned_and_member_access(self):
        module.build_management_links = mock.Mock(
            return_value={
                "configured": True,
                "reason": "",
                "links": {
                    "overview": "https://billing.example/overview",
                    "update_payment_method": "https://billing.example/update",
                    "cancel_subscription": "https://billing.example/cancel",
                },
            }
        )
        self.repo.upsert_subscription(
            {
                "subscription_id": "personal-sub",
                "user_id": "user-1",
                "provider": "apple",
                "plan_code": "producer",
                "status": "active",
                "product_code": "producer_monthly",
                "next_billed_at": "2026-06-21T00:00:00Z",
                "management_channel": "apple",
            }
        )
        self.repo.upsert_subscription(
            {
                "subscription_id": "studio-sub",
                "user_id": "user-1",
                "provider": "paddle",
                "customer_id": "ctm-1",
                "plan_code": "studio",
                "status": "active",
                "product_code": "studio_monthly",
                "seat_count": 7,
                "extra_storage_tb": 1,
                "billing_amount": 149000,
                "billing_currency": "KRW",
                "management_channel": "web",
            }
        )
        module.collaboration_repo.build_user_access_snapshot.return_value = {
            "organizations": [
                {
                    "organization_id": "org-edu",
                    "name": "Music School",
                    "plan_code": "education",
                    "status": "active",
                    "membership_status": "active",
                    "membership_role": "student",
                    "seat_limit": 30,
                    "seats_used": 12,
                }
            ],
            "summary": {},
        }

        response = module.handler(
            {
                "rawPath": "/v1/billing/subscriptions",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        self.assertEqual(payload["personal"][0]["subscription_id"], "personal-sub")
        self.assertEqual(payload["personal"][0]["plan_code"], "producer")
        self.assertEqual(payload["personal"][0]["plan_name"], "Producer")
        self.assertEqual(payload["personal"][0]["billing_cycle"], "monthly")
        self.assertIn("apps.apple.com", payload["personal"][0]["manage_url"])
        self.assertTrue(payload["personal"][0]["billing_owner"])
        self.assertEqual(payload["team"][0]["subscription_id"], "studio-sub")
        self.assertEqual(payload["team"][0]["plan_code"], "studio")
        self.assertEqual(payload["team"][0]["plan_name"], "Studio")
        self.assertEqual(payload["team"][0]["seat_count"], 7)
        self.assertEqual(payload["team"][0]["amount"], 149000)
        self.assertEqual(payload["team"][0]["currency"], "KRW")
        self.assertEqual(payload["team"][0]["price_formatted"], "₩149,000")
        self.assertEqual(payload["team"][0]["billing_cycle"], "monthly")
        self.assertEqual(payload["team"][0]["manage_url"], "https://billing.example/overview")
        self.assertEqual(payload["member_of"][0]["organization_id"], "org-edu")
        self.assertEqual(payload["member_of"][0]["plan_code"], "education")
        self.assertEqual(payload["member_of"][0]["organization_name"], "Music School")
        self.assertFalse(payload["member_of"][0]["billing_owner"])
        self.assertFalse(payload["member_of"][0]["manageable"])

    def test_billing_subscriptions_omits_toss_one_time_management_url(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-payment:order-1",
                "user_id": "user-1",
                "provider": "toss",
                "plan_code": "studio",
                "status": "active",
                "product_code": "studio_monthly",
                "billing_amount": 149000,
                "billing_currency": "KRW",
                "management_channel": "web",
                "one_time_checkout_url": "/payment/checkout?order_id=order-1",
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/subscriptions",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        item = payload["team"][0]
        self.assertEqual(item["provider"], "toss")
        self.assertEqual(item["manage_url"], "")
        self.assertEqual(item["update_payment_method_url"], "")
        self.assertEqual(item["cancel_subscription_url"], "")
        self.assertFalse(item["manageable"])
        self.assertEqual(item["provider_management"]["reason"], "toss_one_time_payment")
        self.assertEqual(item["one_time_checkout_url"], "/payment/checkout?order_id=order-1")

    def test_billing_subscriptions_marks_toss_recurring_management_configured(self):
        self.repo.upsert_subscription(
            {
                "subscription_id": "toss-billing:customer-1:producer_monthly",
                "user_id": "user-1",
                "provider": "toss",
                "customer_id": "customer-1",
                "plan_code": "producer",
                "status": "active",
                "product_code": "producer_monthly",
                "next_billed_at": "2026-06-18T00:00:00Z",
                "billing_key_parameter_name": "/mixroom/payment-credentials/test/toss/customer-1",
                "billing_amount": 29000,
                "billing_currency": "KRW",
                "management_channel": "toss",
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/subscriptions",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        payload = decode_json_response(response)
        item = payload["personal"][0]
        self.assertEqual(item["provider"], "toss")
        self.assertEqual(item["customer_key"], "customer-1")
        self.assertEqual(item["provider_management"]["configured"], True)
        self.assertEqual(item["provider_management"]["reason"], "")
        self.assertEqual(item["next_billed_at"], "2026-06-18T00:00:00Z")

    def test_verification_conflict_returns_409(self):
        module.verify_google_purchase = mock.Mock(
            side_effect=module.ProviderVerificationError(
                "Google Play purchase is already linked to another Mixroom account.",
                status_code=409,
            )
        )

        response = module.handler(
            {
                "rawPath": "/v1/billing/mobile/google/verify",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps({"purchase_token": "purchase-token"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 409)
        self.assertIn("already linked", response["body"])
        module.capture_event.assert_not_called()

    def test_unauthorized_without_user(self):
        module.extract_user_id_from_event = lambda event: ""

        response = module.handler({}, object())

        self.assertEqual(response["statusCode"], 401)


if __name__ == "__main__":
    unittest.main()
