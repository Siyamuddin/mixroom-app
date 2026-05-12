import importlib
import json
import unittest
from unittest import mock

from support import FakeBillingRepo, FakeEventBridge, decode_json_response

api_billing = importlib.import_module("src.handlers.api_billing")
projector = importlib.import_module("src.handlers.projector")


class SubscriptionFlowTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.eventbridge = FakeEventBridge()

        self.original_billing_repo = api_billing.repo
        self.original_billing_extract_user_id = api_billing.extract_user_id_from_event
        self.original_billing_verify_google = api_billing.verify_google_purchase
        self.original_capture_event = api_billing.capture_event
        self.original_projector_repo = projector.repo
        self.original_projector_eventbridge = projector.eventbridge

        api_billing.repo = self.repo
        api_billing.extract_user_id_from_event = lambda event: "user-1"
        api_billing.capture_event = mock.Mock()
        projector.repo = self.repo
        projector.eventbridge = self.eventbridge

    def tearDown(self):
        api_billing.repo = self.original_billing_repo
        api_billing.extract_user_id_from_event = self.original_billing_extract_user_id
        api_billing.verify_google_purchase = self.original_billing_verify_google
        api_billing.capture_event = self.original_capture_event
        projector.repo = self.original_projector_repo
        projector.eventbridge = self.original_projector_eventbridge

    def test_google_verify_to_projection_updates_entitlement(self):
        api_billing.verify_google_purchase = mock.Mock(
            return_value={
                "provider_event_id": "google:verify-1",
                "user_id": "user-1",
                "provider_payload": {"state": "ACTIVE"},
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "plan_code": "producer",
                    "status": "active",
                    "expires_at": "2099-04-20T00:00:00+00:00",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                    "management_channel": "google",
                    "product_id": "mixroom_producer_monthly",
                },
            }
        )

        response = api_billing.handler(
            {
                "rawPath": "/v1/billing/mobile/google/verify",
                "requestContext": {"http": {"method": "POST"}},
                "body": json.dumps(
                    {
                        "purchase_token": "purchase-token",
                        "product_id": "mixroom_producer_monthly",
                    }
                ),
            },
            object(),
        )
        payload = decode_json_response(response)

        self.assertTrue(payload["accepted"])
        projector.handler(
            {"Records": [{"body": json.dumps({"event_id": payload["event_id"]})}]},
            object(),
        )

        entitlement = self.repo.get_entitlement("user-1")
        self.assertEqual(entitlement["plan_code"], "producer")
        self.assertEqual(entitlement["status"], "active")
        self.assertEqual(entitlement["source_subscription_id"], "sub-1")
        self.assertEqual(len(self.eventbridge.entries), 1)


if __name__ == "__main__":
    unittest.main()
