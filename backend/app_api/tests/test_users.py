from __future__ import annotations

import os
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

for key, value in {
    "BILLING_EVENTS_TABLE": "billing-events",
    "SUBSCRIPTIONS_TABLE": "subscriptions",
    "ENTITLEMENTS_TABLE": "entitlements",
    "CATALOG_MAPPINGS_TABLE": "catalog",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconciliation-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
}.items():
    os.environ.setdefault(key, value)

from src.common.users import (
    apply_user_profile_patch,
    build_user_profile_from_claims,
    validate_username,
)


class BuildUserProfileFromClaimsTests(unittest.TestCase):
    def test_builds_minimal_profile_from_claims(self) -> None:
        record = build_user_profile_from_claims(
            {
                "sub": "user-123",
                "email": "Test.User@example.com",
                "name": "Test User",
                "email_verified": "true",
            }
        )

        self.assertEqual(record["user_id"], "user-123")
        self.assertEqual(record["email"], "test.user@example.com")
        self.assertEqual(record["display_name"], "Test User")
        self.assertTrue(record["email_verified"])
        self.assertEqual(record["profile_status"], "active")
        self.assertEqual(record["onboarding_state"], "bootstrap_only")
        self.assertIsNone(record["accepted_terms_version"])
        self.assertIsNone(record["accepted_privacy_version"])
        self.assertIsNone(record["accepted_at"])
        self.assertFalse(record["newsletter_opt_in"])
        self.assertIsNone(record["newsletter_opt_in_at"])
        self.assertIsNone(record["given_name"])
        self.assertIsNone(record["family_name"])
        self.assertIsNone(record["birthdate"])
        self.assertIsNone(record["music_profile"])

    def test_preserves_existing_platform_fields(self) -> None:
        record = build_user_profile_from_claims(
            {
                "sub": "user-123",
                "email": "hello@example.com",
            },
            existing={
                "display_name": "Existing Name",
                "username": "mixroomer",
                "given_name": "Existing",
                "family_name": "Name",
                "birthdate": "1999-04-11",
                "music_profile": "producer",
                "avatar_url": "https://cdn.mixroom.ai/avatar.png",
                "profile_status": "active",
                "onboarding_state": "signup_complete",
                "accepted_terms_version": "2026-03-10",
                "accepted_privacy_version": "2026-03-10",
                "accepted_at": "2026-03-10T00:00:00+00:00",
                "newsletter_opt_in": True,
                "newsletter_opt_in_at": "2026-03-10T00:00:00+00:00",
                "created_at": "2026-01-01T00:00:00+00:00",
            },
        )

        self.assertEqual(record["display_name"], "Existing Name")
        self.assertEqual(record["username"], "mixroomer")
        self.assertEqual(record["username_lc"], "mixroomer")
        self.assertEqual(record["given_name"], "Existing")
        self.assertEqual(record["family_name"], "Name")
        self.assertEqual(record["birthdate"], "1999-04-11")
        self.assertEqual(record["music_profile"], "producer")
        self.assertEqual(
            record["avatar_url"],
            "https://cdn.mixroom.ai/avatar.png",
        )
        self.assertEqual(record["onboarding_state"], "signup_complete")
        self.assertEqual(record["accepted_terms_version"], "2026-03-10")
        self.assertEqual(record["accepted_privacy_version"], "2026-03-10")
        self.assertEqual(record["accepted_at"], "2026-03-10T00:00:00+00:00")
        self.assertTrue(record["newsletter_opt_in"])
        self.assertEqual(
            record["newsletter_opt_in_at"],
            "2026-03-10T00:00:00+00:00",
        )
        self.assertEqual(record["created_at"], "2026-01-01T00:00:00+00:00")

    def test_rejects_reserved_username(self) -> None:
        self.assertEqual(validate_username("admin"), "That username is reserved.")

    def test_rejects_invalid_username_shape(self) -> None:
        self.assertIsNotNone(validate_username("_bad"))
        self.assertIsNotNone(validate_username("bad__handle"))

    def test_allows_single_character_username(self) -> None:
        self.assertIsNone(validate_username("a"))

    def test_apply_patch_normalizes_username_and_bio(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": None,
                "username_lc": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "username": "MixRoom_User",
                "given_name": "  Mix  ",
                "family_name": "  Room  ",
                "birthdate": "1998-08-09",
                "bio": "  producer and vocalist  ",
                "music_profile": "artist",
            },
        )

        self.assertEqual(updated["username"], "mixroom_user")
        self.assertEqual(updated["username_lc"], "mixroom_user")
        self.assertEqual(updated["given_name"], "Mix")
        self.assertEqual(updated["family_name"], "Room")
        self.assertEqual(updated["birthdate"], "1998-08-09")
        self.assertEqual(updated["bio"], "producer and vocalist")
        self.assertEqual(updated["music_profile"], "artist")
        self.assertEqual(updated["onboarding_state"], "profile_ready")

    def test_apply_patch_accepts_student_music_profile(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": "mixroom_user",
                "username_lc": "mixroom_user",
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "music_profile": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "music_profile": "student",
            },
        )

        self.assertEqual(updated["music_profile"], "student")

    def test_apply_patch_sets_display_name_from_username_when_display_name_is_email_fallback(
        self,
    ) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Hello",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": None,
                "username_lc": None,
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "username": "new_handle",
            },
        )

        self.assertEqual(updated["username"], "new_handle")
        self.assertEqual(updated["display_name"], "new_handle")

    def test_apply_patch_keeps_existing_display_name_when_setting_username(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": None,
                "username_lc": None,
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "username": "new_handle",
            },
        )

        self.assertEqual(updated["username"], "new_handle")
        self.assertEqual(updated["display_name"], "Existing Name")

    def test_apply_patch_records_legal_consent(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": None,
                "username_lc": None,
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "accepted_terms_version": "2026-03-10",
                "accepted_privacy_version": "2026-03-10",
                "accepted_at": "2026-03-10T01:02:03Z",
                "username": "hello_user",
                "birthdate": "1997-12-24",
                "music_profile": "music_for_work",
                "newsletter_opt_in": True,
                "newsletter_opt_in_at": "2026-03-10T01:02:03Z",
            },
        )

        self.assertEqual(updated["accepted_terms_version"], "2026-03-10")
        self.assertEqual(updated["accepted_privacy_version"], "2026-03-10")
        self.assertEqual(updated["accepted_at"], "2026-03-10T01:02:03+00:00")
        self.assertTrue(updated["newsletter_opt_in"])
        self.assertEqual(
            updated["newsletter_opt_in_at"],
            "2026-03-10T01:02:03+00:00",
        )
        self.assertEqual(updated["birthdate"], "1997-12-24")
        self.assertEqual(updated["music_profile"], "music_for_work")
        self.assertEqual(updated["onboarding_state"], "signup_complete")

    def test_apply_patch_allows_signup_completion_without_birthdate(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": None,
                "username_lc": None,
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "bootstrap_only",
                "accepted_terms_version": None,
                "accepted_privacy_version": None,
                "accepted_at": None,
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 1,
            },
            {
                "accepted_terms_version": "2026-03-10",
                "accepted_privacy_version": "2026-03-10",
                "username": "hello_user",
                "birthdate": None,
            },
        )

        self.assertIsNone(updated["birthdate"])
        self.assertEqual(updated["username"], "hello_user")
        self.assertEqual(updated["onboarding_state"], "signup_complete")

    def test_apply_patch_preserves_legacy_welcome_seen_marker(self) -> None:
        updated = apply_user_profile_patch(
            {
                "user_id": "user-123",
                "email": "hello@example.com",
                "display_name": "Existing Name",
                "email_verified": True,
                "cognito_username": "hello@example.com",
                "auth_provider": "email",
                "username": "hello_user",
                "username_lc": "hello_user",
                "given_name": None,
                "family_name": None,
                "birthdate": None,
                "avatar_url": None,
                "bio": None,
                "profile_status": "active",
                "onboarding_state": "signup_complete",
                "accepted_terms_version": "2026-03-10",
                "accepted_privacy_version": "2026-03-10",
                "accepted_at": "2026-03-10T00:00:00+00:00",
                "newsletter_opt_in": False,
                "newsletter_opt_in_at": None,
                "created_at": "2026-01-01T00:00:00+00:00",
                "updated_at": "2026-01-01T00:00:00+00:00",
                "last_seen_at": "2026-01-01T00:00:00+00:00",
                "schema_version": 4,
            },
            {
                "onboarding_state": "signup_complete_welcome_seen",
            },
        )

        self.assertEqual(updated["onboarding_state"], "signup_complete_welcome_seen")

    def test_rejects_unsupported_music_profile(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "Music profile must be one of the supported options.",
        ):
            apply_user_profile_patch(
                {
                    "user_id": "user-123",
                    "email": "hello@example.com",
                    "display_name": "Existing Name",
                    "email_verified": True,
                    "cognito_username": "hello@example.com",
                    "auth_provider": "email",
                    "username": "hello_user",
                    "username_lc": "hello_user",
                    "given_name": None,
                    "family_name": None,
                    "birthdate": "1997-12-24",
                    "music_profile": None,
                    "avatar_url": None,
                    "bio": None,
                    "profile_status": "active",
                    "onboarding_state": "bootstrap_only",
                    "accepted_terms_version": None,
                    "accepted_privacy_version": None,
                    "accepted_at": None,
                    "newsletter_opt_in": False,
                    "newsletter_opt_in_at": None,
                    "created_at": "2026-01-01T00:00:00+00:00",
                    "updated_at": "2026-01-01T00:00:00+00:00",
                    "last_seen_at": "2026-01-01T00:00:00+00:00",
                    "schema_version": 1,
                },
                {
                    "music_profile": "professional_vibes",
                },
            )

    def test_rejects_underage_birthdate(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "You must be at least 13 years old to use Mixroom.",
        ):
            apply_user_profile_patch(
                {
                    "user_id": "user-123",
                    "email": "hello@example.com",
                    "display_name": "Existing Name",
                    "email_verified": True,
                    "cognito_username": "hello@example.com",
                    "auth_provider": "email",
                    "username": "hello_user",
                    "username_lc": "hello_user",
                    "given_name": None,
                    "family_name": None,
                    "birthdate": None,
                    "avatar_url": None,
                    "bio": None,
                    "profile_status": "active",
                    "onboarding_state": "bootstrap_only",
                    "accepted_terms_version": None,
                    "accepted_privacy_version": None,
                    "accepted_at": None,
                    "newsletter_opt_in": False,
                    "newsletter_opt_in_at": None,
                    "created_at": "2026-01-01T00:00:00+00:00",
                    "updated_at": "2026-01-01T00:00:00+00:00",
                    "last_seen_at": "2026-01-01T00:00:00+00:00",
                    "schema_version": 1,
                },
                {
                    "birthdate": "2016-03-14",
                },
            )


if __name__ == "__main__":
    unittest.main()
