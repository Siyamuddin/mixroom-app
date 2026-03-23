import importlib
import json
import unittest
from unittest import mock

from support import FakeBillingRepo, decode_json_response

module = importlib.import_module("src.handlers.webhooks")


class WebhookHandlerTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()
        self.original_repo = module.repo
        self.original_verify_apple_notification = module.verify_apple_notification
        self.original_build_google_webhook_event = module.build_google_webhook_event
        self.original_verify_google_webhook_request = module.verify_google_webhook_request
        self.original_verify_webhook_signature = module.verify_webhook_signature
        module.repo = self.repo

    def tearDown(self):
        module.repo = self.original_repo
        module.verify_apple_notification = self.original_verify_apple_notification
        module.build_google_webhook_event = self.original_build_google_webhook_event
        module.verify_google_webhook_request = self.original_verify_google_webhook_request
        module.verify_webhook_signature = self.original_verify_webhook_signature

    def test_apple_webhook_persists_event(self):
        module.verify_apple_notification = mock.Mock(
            return_value={
                "provider_event_id": "apple:uuid-1",
                "user_id": "user-1",
                "provider_payload": {"notificationType": "DID_RENEW"},
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "sub-1",
                    "tier": "pro",
                    "status": "active",
                    "source_occurred_at": "2026-03-20T00:00:00+00:00",
                },
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/apple",
                "body": json.dumps({"signedPayload": "signed.notification"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])

    def test_google_webhook_persists_event(self):
        module.verify_google_webhook_request = mock.Mock()
        module.build_google_webhook_event = mock.Mock(
            return_value={
                "provider_event_id": "pubsub-message-1",
                "user_id": "user-1",
                "provider_payload": {"subscriptionNotification": {}},
                "normalized": {
                    "provider": "google",
                    "subscription_id": "sub-1",
                    "tier": "pro",
                    "status": "active",
                    "source_occurred_at": "2026-03-21T00:00:00+00:00",
                },
            }
        )

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/google",
                "headers": {"Authorization": "Bearer token"},
                "body": json.dumps({"message": {"data": ""}}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertEqual(payload["provider"], "google")
        self.assertEqual(self.repo.queued_projection_ids, [payload["event_id"]])

    def test_invalid_paddle_signature_returns_401(self):
        module.verify_webhook_signature = mock.Mock(return_value=False)

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/paddle",
                "headers": {"Paddle-Signature": "bad"},
                "body": json.dumps({"event_type": "subscription_updated"}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 401)
        self.assertEqual(self.repo.queued_projection_ids, [])

    def test_duplicate_toss_webhook_returns_accepted_false(self):
        module.verify_webhook_signature = mock.Mock(return_value=True)
        event = {
            "rawPath": "/v1/webhooks/toss",
            "headers": {"X-Signature": "sig"},
            "body": json.dumps(
                {
                    "id": "evt-1",
                    "user_id": "user-1",
                    "subscription_id": "sub-1",
                    "status": "active",
                }
            ),
        }

        first = decode_json_response(module.handler(event, object()))
        second = decode_json_response(module.handler(event, object()))

        self.assertTrue(first["accepted"])
        self.assertFalse(second["accepted"])
        self.assertEqual(len(self.repo.queued_projection_ids), 1)

    def test_provider_verification_error_bubbles_status(self):
        module.verify_google_webhook_request = mock.Mock()
        module.build_google_webhook_event = mock.Mock(
            side_effect=module.ProviderVerificationError(
                "Google RTDN test notification received.",
                status_code=202,
            )
        )

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/google",
                "body": json.dumps({"message": {"data": ""}}),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertFalse(payload["accepted"])
        self.assertIn("test notification", payload["error"])


if __name__ == "__main__":
    unittest.main()
