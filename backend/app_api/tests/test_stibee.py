from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path

_TESTS_DIR = Path(__file__).resolve().parent
if str(_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(_TESTS_DIR))

import support  # noqa: F401  # ensures test support side effects

module = importlib.import_module("src.common.stibee")


class _FakeStibeeClient:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def upsert_subscriber(
        self,
        *,
        list_id: str,
        email: str,
        status: str,
        marketing_allowed: bool,
        fields=None,
    ) -> None:
        self.calls.append(
            {
                "list_id": list_id,
                "email": email,
                "status": status,
                "marketing_allowed": marketing_allowed,
                "fields": dict(fields or {}),
            }
        )


class StibeeSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_client = module._StibeeClient
        self.original_access_token = module.config.STIBEE_ACCESS_TOKEN
        self.original_access_token_secret_arn = module.config.STIBEE_ACCESS_TOKEN_SECRET_ARN
        self.original_app_signups_list_id = module.config.STIBEE_APP_SIGNUPS_LIST_ID
        self.original_newsletter_list_id = module.config.STIBEE_NEWSLETTER_LIST_ID
        self.original_language_field_key = module.config.STIBEE_LANGUAGE_FIELD_KEY
        self.original_name_field_key = module.config.STIBEE_NAME_FIELD_KEY

        self.fake_client = _FakeStibeeClient()
        module._StibeeClient = lambda: self.fake_client
        module.config.STIBEE_ACCESS_TOKEN = "test-token"
        module.config.STIBEE_ACCESS_TOKEN_SECRET_ARN = ""
        module.config.STIBEE_APP_SIGNUPS_LIST_ID = "483997"
        module.config.STIBEE_NEWSLETTER_LIST_ID = "483373"
        module.config.STIBEE_LANGUAGE_FIELD_KEY = "language"
        module.config.STIBEE_NAME_FIELD_KEY = ""

    def tearDown(self) -> None:
        module._StibeeClient = self.original_client
        module.config.STIBEE_ACCESS_TOKEN = self.original_access_token
        module.config.STIBEE_ACCESS_TOKEN_SECRET_ARN = (
            self.original_access_token_secret_arn
        )
        module.config.STIBEE_APP_SIGNUPS_LIST_ID = self.original_app_signups_list_id
        module.config.STIBEE_NEWSLETTER_LIST_ID = self.original_newsletter_list_id
        module.config.STIBEE_LANGUAGE_FIELD_KEY = self.original_language_field_key
        module.config.STIBEE_NAME_FIELD_KEY = self.original_name_field_key

    def test_locale_only_change_syncs_signup_and_newsletter_lists_for_subscribed_user(self) -> None:
        previous = {
            "user_id": "user-1",
            "email": "user@example.com",
            "display_name": "User Example",
            "onboarding_state": "signup_complete",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": True,
            "newsletter_opt_in_at": "2026-03-11T00:00:00+00:00",
            "locale_code": "en",
            "updated_at": "2026-03-11T00:00:00+00:00",
        }
        next_profile = {
            **previous,
            "locale_code": "ko",
            "updated_at": "2026-04-13T03:00:00+00:00",
        }

        module.sync_user_profile(
            previous_profile=previous,
            next_profile=next_profile,
            locale_code=None,
        )

        self.assertEqual(len(self.fake_client.calls), 2)
        self.assertEqual(
            [call["list_id"] for call in self.fake_client.calls],
            ["483997", "483373"],
        )
        self.assertEqual(
            [call["fields"]["language"] for call in self.fake_client.calls],
            ["ko", "ko"],
        )
        self.assertEqual(self.fake_client.calls[1]["status"], "subscribed")

    def test_locale_only_change_does_not_sync_newsletter_list_for_unsubscribed_user(self) -> None:
        previous = {
            "user_id": "user-1",
            "email": "user@example.com",
            "display_name": "User Example",
            "onboarding_state": "signup_complete",
            "accepted_at": "2026-03-10T00:00:00+00:00",
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "locale_code": "en",
            "updated_at": "2026-03-11T00:00:00+00:00",
        }
        next_profile = {
            **previous,
            "locale_code": "ko",
            "updated_at": "2026-04-13T03:00:00+00:00",
        }

        module.sync_user_profile(
            previous_profile=previous,
            next_profile=next_profile,
            locale_code=None,
        )

        self.assertEqual(len(self.fake_client.calls), 1)
        self.assertEqual(self.fake_client.calls[0]["list_id"], "483997")
        self.assertEqual(self.fake_client.calls[0]["fields"]["language"], "ko")


if __name__ == "__main__":
    unittest.main()
