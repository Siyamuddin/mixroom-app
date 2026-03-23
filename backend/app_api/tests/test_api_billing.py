import importlib
import json
import unittest
from unittest import mock

from support import FakeBillingRepo, decode_json_response

module = importlib.import_module("src.handlers.api_billing")


class ApiBillingTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.original_repo = module.repo
        self.original_extract_user_id = module.extract_user_id_from_event
        self.original_capture_event = module.capture_event
        self.original_verify_apple_purchase = module.verify_apple_purchase
        self.original_verify_google_purchase = module.verify_google_purchase
        module.repo = self.repo
        module.extract_user_id_from_event = lambda event: "user-1"
        module.capture_event = mock.Mock()

    def tearDown(self):
        module.repo = self.original_repo
        module.extract_user_id_from_event = self.original_extract_user_id
        module.capture_event = self.original_capture_event
        module.verify_apple_purchase = self.original_verify_apple_purchase
        module.verify_google_purchase = self.original_verify_google_purchase

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
        self.assertEqual(len(self.repo.queued_projection_ids), 1)
        event = self.repo.get_billing_event(self.repo.queued_projection_ids[0])
        self.assertEqual(event["event_type"], "checkout_session_created")

    def test_mobile_verify_google_persists_event_and_tracks_analytics(self):
        module.verify_google_purchase = mock.Mock(
            return_value={
                "provider_event_id": "google:event-1",
                "user_id": "user-1",
                "provider_payload": {"state": "ACTIVE"},
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "tier": "pro",
                    "status": "active",
                    "product_id": "mixroom_pro_monthly",
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
                        "product_id": "mixroom_pro_monthly",
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
        module.capture_event.assert_called_once()
        tracked_args = module.capture_event.call_args.args
        tracked_kwargs = module.capture_event.call_args.kwargs
        self.assertEqual(tracked_args[0], "subscription_started")
        self.assertEqual(tracked_kwargs["distinct_id"], "device-1")
        self.assertEqual(tracked_kwargs["properties"]["billing_cycle"], "monthly")
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])

    def test_duplicate_mobile_verify_returns_accepted_false_without_tracking(self):
        module.verify_apple_purchase = mock.Mock(
            return_value={
                "provider_event_id": "apple:event-1",
                "user_id": "user-1",
                "provider_payload": {"transaction": "ok"},
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "apple-sub-1",
                    "tier": "pro",
                    "status": "active",
                    "product_id": "mixroom_pro_monthly",
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
                "tier": "pro",
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
        self.assertIn("play.google.com", payload["url"])

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
