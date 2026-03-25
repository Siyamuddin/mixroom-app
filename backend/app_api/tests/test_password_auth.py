from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

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
    "USERS_TABLE": "users",
    "USERNAME_CLAIMS_TABLE": "username-claims",
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
    "APP_AUTH_SECRET_ARN": "app-auth-secret",
}.items():
    os.environ.setdefault(key, value)

if "boto3" not in sys.modules:
    boto3_stub = ModuleType("boto3")
    boto3_stub.client = mock.Mock(return_value=mock.Mock())
    boto3_stub.resource = mock.Mock(
        return_value=SimpleNamespace(Table=mock.Mock(return_value=mock.Mock()))
    )
    sys.modules["boto3"] = boto3_stub
    dynamodb_stub = ModuleType("boto3.dynamodb")
    conditions_stub = ModuleType("boto3.dynamodb.conditions")
    conditions_stub.Attr = mock.Mock()
    conditions_stub.Key = mock.Mock()
    types_stub = ModuleType("boto3.dynamodb.types")

    class _TypeSerializer:
        def serialize(self, value):
            return value

    types_stub.TypeSerializer = _TypeSerializer
    dynamodb_stub.conditions = conditions_stub
    dynamodb_stub.types = types_stub
    sys.modules["boto3.dynamodb"] = dynamodb_stub
    sys.modules["boto3.dynamodb.conditions"] = conditions_stub
    sys.modules["boto3.dynamodb.types"] = types_stub

if "botocore.exceptions" not in sys.modules:
    botocore_stub = ModuleType("botocore")
    exceptions_stub = ModuleType("botocore.exceptions")

    class _ClientError(Exception):
        def __init__(self, response: dict, operation_name: str = "") -> None:
            super().__init__(operation_name)
            self.response = response

    exceptions_stub.ClientError = _ClientError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub

from src.common import native_auth  # noqa: E402


class _FakeRepo:
    def __init__(self, *, account=None, profile=None) -> None:
        self.account = dict(account or {})
        self.profile = dict(profile or {})
        self.session_records = []

    def get_auth_account_by_email(self, email_lc):
        if self.account and self.account.get("email_lc") == email_lc:
            return dict(self.account)
        return None

    def get_user_profile_by_username(self, username_lc):
        if self.profile and self.profile.get("username_lc") == username_lc:
            return dict(self.profile)
        return None

    def get_auth_account(self, user_id):
        if self.account and self.account.get("user_id") == user_id:
            return dict(self.account)
        return None

    def get_user_profile(self, user_id):
        if self.profile and self.profile.get("user_id") == user_id:
            return dict(self.profile)
        return {}

    def put_auth_session(self, record):
        self.session_records.append(dict(record))

    def put_auth_account(self, record):
        self.account = dict(record)

    def upsert_user_profile(self, profile, *, previous_username_lc=None):
        self.profile = dict(profile)


class CompletePasswordSignInTests(unittest.TestCase):
    def test_signs_in_with_username(self) -> None:
        account = {
            "user_id": "user-123",
            "email": "hello@example.com",
            "email_lc": "hello@example.com",
            "auth_provider": "email",
            "email_verified": True,
            "password_salt": "salt-123",
            "password_hash": native_auth._hash_password(  # noqa: SLF001
                password="correct-password",
                salt="salt-123",
            ),
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        profile = {
            "user_id": "user-123",
            "email": "hello@example.com",
            "email_lc": "hello@example.com",
            "display_name": "Hello User",
            "username": "hello_user",
            "username_lc": "hello_user",
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        repo = _FakeRepo(account=account, profile=profile)

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-123_secret",
                "refresh-hash",
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token", "id-token"],
        ):
            result = native_auth.complete_password_sign_in(
                repo,
                identifier="hello_user",
                password="correct-password",
            )

        self.assertEqual(result["user"]["email"], "hello@example.com")
        self.assertEqual(result["user"]["displayName"], "Hello User")
        self.assertEqual(result["tokens"]["accessToken"], "access-token")
        self.assertEqual(len(repo.session_records), 1)
        self.assertEqual(repo.session_records[0]["user_id"], "user-123")

    def test_returns_confirmation_required_for_unconfirmed_user(self) -> None:
        account = {
            "user_id": "user-789",
            "email": "pending@example.com",
            "email_lc": "pending@example.com",
            "auth_provider": "email",
            "email_verified": False,
            "password_salt": "salt-789",
            "password_hash": native_auth._hash_password(  # noqa: SLF001
                password="correct-password",
                salt="salt-789",
            ),
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        profile = {
            "user_id": "user-789",
            "email": "pending@example.com",
            "email_lc": "pending@example.com",
            "display_name": "Pending User",
            "username": "pending_user",
            "username_lc": "pending_user",
        }
        repo = _FakeRepo(account=account, profile=profile)

        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.complete_password_sign_in(
                repo,
                identifier="pending_user",
                password="correct-password",
            )

        error = raised.exception
        self.assertEqual(error.code, "EMAIL_CONFIRMATION_REQUIRED")
        self.assertEqual(error.details.get("email"), "pending@example.com")

    def test_rejects_unknown_non_email_identifier_without_legacy_fallback(self) -> None:
        repo = _FakeRepo(account=None, profile=None)

        with mock.patch.object(
            native_auth,
            "sign_in_legacy_cognito_password",
        ) as legacy_sign_in:
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.complete_password_sign_in(
                    repo,
                    identifier="legacy_only_username",
                    password="correct-password",
                )

        error = raised.exception
        self.assertEqual(error.code, "INVALID_CREDENTIALS")
        legacy_sign_in.assert_not_called()


if __name__ == "__main__":
    unittest.main()
