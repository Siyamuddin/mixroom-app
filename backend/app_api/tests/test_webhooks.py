import importlib
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

_TESTS_DIR = Path(__file__).resolve().parent
if str(_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(_TESTS_DIR))

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
        self.original_stibee_newsletter_list_id = module.config.STIBEE_NEWSLETTER_LIST_ID
        self.original_stibee_allowed_ips = module.config.STIBEE_WEBHOOK_ALLOWED_IPS
        self.original_stibee_shared_secret = module.config.STIBEE_WEBHOOK_SHARED_SECRET
        self.original_stibee_shared_secret_arn = module.config.STIBEE_WEBHOOK_SHARED_SECRET_ARN
        module.repo = self.repo
        module.config.STIBEE_NEWSLETTER_LIST_ID = "483373"
        module.config.STIBEE_WEBHOOK_ALLOWED_IPS = frozenset({"52.78.132.66"})
        module.config.STIBEE_WEBHOOK_SHARED_SECRET = ""
        module.config.STIBEE_WEBHOOK_SHARED_SECRET_ARN = ""

    def tearDown(self):
        module.repo = self.original_repo
        module.verify_apple_notification = self.original_verify_apple_notification
        module.build_google_webhook_event = self.original_build_google_webhook_event
        module.verify_google_webhook_request = self.original_verify_google_webhook_request
        module.verify_webhook_signature = self.original_verify_webhook_signature
        module.config.STIBEE_NEWSLETTER_LIST_ID = self.original_stibee_newsletter_list_id
        module.config.STIBEE_WEBHOOK_ALLOWED_IPS = self.original_stibee_allowed_ips
        module.config.STIBEE_WEBHOOK_SHARED_SECRET = self.original_stibee_shared_secret
        module.config.STIBEE_WEBHOOK_SHARED_SECRET_ARN = (
            self.original_stibee_shared_secret_arn
        )

    def test_apple_webhook_persists_event(self):
        module.verify_apple_notification = mock.Mock(
            return_value={
                "provider_event_id": "apple:uuid-1",
                "user_id": "user-1",
                "provider_payload": {"notificationType": "DID_RENEW"},
                "normalized": {
                    "provider": "apple",
                    "subscription_id": "sub-1",
                    "plan_code": "producer",
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
                    "plan_code": "producer",
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

    def test_stibee_unsubscribe_updates_user_profile(self):
        self.repo.user_profiles["user-1"] = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "2026-03-10",
            "accepted_privacy_version": "2026-03-10",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": True,
            "newsletter_opt_in_at": "2026-03-11T00:00:00+00:00",
            "locale_code": "en",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-03-11T00:00:00+00:00",
            "last_seen_at": "2026-03-11T00:00:00+00:00",
            "schema_version": 4,
        }

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/stibee",
                "headers": {"x-forwarded-for": "52.78.132.66"},
                "body": json.dumps(
                    {
                        "addressBookId": "483373",
                        "action": "UNSUBSCRIBED",
                        "occurredAt": "2026-04-13T12:00:00+09:00",
                        "subscribers": [
                            {
                                "email": "user@example.com",
                            }
                        ],
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["provider"], "stibee")
        self.assertEqual(payload["updated_users"], 1)
        self.assertFalse(self.repo.user_profiles["user-1"]["newsletter_opt_in"])
        self.assertIsNone(self.repo.user_profiles["user-1"]["newsletter_opt_in_at"])
        self.assertEqual(self.repo.user_profile_upserts, [])
        self.assertEqual(len(self.repo.user_profile_newsletter_updates), 1)

    def test_stibee_resubscribe_updates_user_profile(self):
        self.repo.user_profiles["user-1"] = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "2026-03-10",
            "accepted_privacy_version": "2026-03-10",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "locale_code": "ko",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-03-11T00:00:00+00:00",
            "last_seen_at": "2026-03-11T00:00:00+00:00",
            "schema_version": 4,
        }

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/stibee",
                "headers": {"x-forwarded-for": "52.78.132.66"},
                "body": json.dumps(
                    {
                        "addressBookId": "483373",
                        "action": "RESUBSCRIBED",
                        "occurredAt": "2026-04-13T12:00:00+09:00",
                        "subscribers": [
                            {
                                "email": "user@example.com",
                            }
                        ],
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        self.assertTrue(self.repo.user_profiles["user-1"]["newsletter_opt_in"])
        self.assertEqual(
            self.repo.user_profiles["user-1"]["newsletter_opt_in_at"],
            "2026-04-13T03:00:00+00:00",
        )
        self.assertEqual(self.repo.user_profile_upserts, [])
        self.assertEqual(len(self.repo.user_profile_newsletter_updates), 1)

    def test_stibee_documented_payload_without_occurred_at_updates_user_profile(self):
        self.repo.user_profiles["user-1"] = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "2026-03-10",
            "accepted_privacy_version": "2026-03-10",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "locale_code": "ko",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-03-11T00:00:00+00:00",
            "last_seen_at": "2026-03-11T00:00:00+00:00",
            "schema_version": 4,
        }

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/stibee",
                "headers": {"x-forwarded-for": "52.78.132.66"},
                "body": json.dumps(
                    {
                        "id": "483373",
                        "action": "RESUBSCRIBED",
                        "eventOccuredBy": "SUBSCRIBER",
                        "subscribers": [
                            {
                                "email": "user@example.com",
                                "name": "User Example",
                            }
                        ],
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["updated_users"], 1)
        self.assertEqual(payload["failed_users"], 0)
        self.assertTrue(self.repo.user_profiles["user-1"]["newsletter_opt_in"])
        self.assertTrue(self.repo.user_profiles["user-1"]["newsletter_opt_in_at"])

    def test_stibee_invalid_occurred_at_is_ignored(self):
        self.repo.user_profiles["user-1"] = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "2026-03-10",
            "accepted_privacy_version": "2026-03-10",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "locale_code": "en",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-03-11T00:00:00+00:00",
            "last_seen_at": "2026-03-11T00:00:00+00:00",
            "schema_version": 4,
        }

        response = module.handler(
            {
                "rawPath": "/v1/webhooks/stibee",
                "headers": {"x-forwarded-for": "52.78.132.66"},
                "body": json.dumps(
                    {
                        "id": "483373",
                        "action": "RESUBSCRIBED",
                        "occurredAt": "2026/04/20 15:40:24",
                        "subscribers": [
                            {
                                "email": "user@example.com",
                            }
                        ],
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["updated_users"], 1)
        self.assertEqual(payload["failed_users"], 0)
        self.assertTrue(self.repo.user_profiles["user-1"]["newsletter_opt_in"])
        self.assertTrue(self.repo.user_profiles["user-1"]["newsletter_opt_in_at"])

    def test_stibee_profile_patch_failure_does_not_return_500(self):
        self.repo.user_profiles["user-1"] = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "onboarding_state": "signup_complete",
            "accepted_terms_version": "2026-03-10",
            "accepted_privacy_version": "2026-03-10",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "locale_code": "en",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-03-11T00:00:00+00:00",
            "last_seen_at": "2026-03-11T00:00:00+00:00",
            "schema_version": 4,
        }

        with mock.patch.object(
            module,
            "apply_user_profile_patch",
            side_effect=ValueError("bad stibee payload"),
        ):
            response = module.handler(
                {
                    "rawPath": "/v1/webhooks/stibee",
                    "headers": {"x-forwarded-for": "52.78.132.66"},
                    "body": json.dumps(
                        {
                            "id": "483373",
                            "action": "RESUBSCRIBED",
                            "subscribers": [
                                {
                                    "email": "user@example.com",
                                }
                            ],
                        }
                    ),
                },
                object(),
            )

        self.assertEqual(response["statusCode"], 202)
        payload = decode_json_response(response)
        self.assertTrue(payload["accepted"])
        self.assertEqual(payload["updated_users"], 0)
        self.assertEqual(payload["failed_users"], 1)
        self.assertFalse(self.repo.user_profiles["user-1"]["newsletter_opt_in"])

    def test_stibee_webhook_rejects_invalid_source_ip(self):
        response = module.handler(
            {
                "rawPath": "/v1/webhooks/stibee",
                "headers": {"x-forwarded-for": "1.2.3.4"},
                "body": json.dumps(
                    {
                        "addressBookId": "483373",
                        "action": "UNSUBSCRIBED",
                        "subscribers": [{"email": "user@example.com"}],
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 401)
        payload = decode_json_response(response)
        self.assertFalse(payload["accepted"])
        self.assertIn("source IP", payload["error"])


if __name__ == "__main__":
    unittest.main()
