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

for module_name in ("src.common.config", "common.config"):
    config_module = sys.modules.get(module_name)
    if config_module is not None:
        config_module.APP_AUTH_SECRET_ARN = os.environ["APP_AUTH_SECRET_ARN"]

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

    class _BotoCoreError(Exception):
        pass

    class _ClientError(Exception):
        def __init__(self, response: dict, operation_name: str = "") -> None:
            super().__init__(operation_name)
            self.response = response

    exceptions_stub.BotoCoreError = _BotoCoreError
    exceptions_stub.ClientError = _ClientError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub

from src.common import native_auth  # noqa: E402


class _FakeRepo:
    def __init__(self) -> None:
        self.accounts: dict[str, dict] = {}
        self.accounts_by_email: dict[str, str] = {}
        self.profiles: dict[str, dict] = {}
        self.sessions: dict[str, dict] = {}
        self.customer_links: dict[str, dict] = {}
        self.entitlements: dict[str, dict] = {}

    def get_auth_account(self, user_id):
        account = self.accounts.get(user_id)
        return dict(account) if account else None

    def get_auth_account_by_email(self, email_lc):
        user_id = self.accounts_by_email.get(email_lc)
        if not user_id:
            return None
        return self.get_auth_account(user_id)

    def put_auth_account(self, record):
        payload = dict(record)
        self.accounts[payload["user_id"]] = payload
        self.accounts_by_email[payload["email_lc"]] = payload["user_id"]

    def delete_auth_account(self, user_id):
        account = self.accounts.pop(user_id, None)
        if account:
            self.accounts_by_email.pop(account.get("email_lc"), None)

    def get_user_profile(self, user_id):
        return dict(self.profiles.get(user_id) or {})

    def get_user_profile_by_username(self, username_lc):
        for profile in self.profiles.values():
            if profile.get("username_lc") == username_lc:
                return dict(profile)
        return None

    def get_user_profile_by_email(self, email_lc):
        for profile in self.profiles.values():
            if profile.get("email_lc") == email_lc:
                return dict(profile)
        return None

    def upsert_user_profile(self, profile, *, previous_username_lc=None):
        self.profiles[profile["user_id"]] = dict(profile)

    def put_auth_session(self, record):
        self.sessions[record["session_id"]] = dict(record)

    def get_auth_session(self, session_id):
        session = self.sessions.get(session_id)
        return dict(session) if session else None

    def delete_auth_session(self, session_id):
        self.sessions.pop(session_id, None)

    def list_auth_sessions_for_user(self, user_id):
        return [
            dict(session)
            for session in self.sessions.values()
            if session.get("user_id") == user_id
        ]

    def delete_auth_sessions_for_user(self, user_id):
        for session_id in list(self.sessions):
            if self.sessions[session_id].get("user_id") == user_id:
                self.sessions.pop(session_id, None)

    def get_entitlement(self, user_id):
        item = self.entitlements.get(user_id)
        return dict(item) if item else None

    def put_entitlement(self, snapshot):
        self.entitlements[snapshot["user_id"]] = dict(snapshot)

    def delete_entitlement(self, user_id):
        self.entitlements.pop(user_id, None)

    def delete_user_profile(self, user_id):
        self.profiles.pop(user_id, None)

    def get_customer_link(self, provider, customer_key):
        item = self.customer_links.get(f"{provider}:{customer_key}")
        return dict(item) if item else None

    def put_customer_link(self, provider, customer_key, user_id, attributes=None):
        payload = {
            "provider": provider,
            "customer_key": customer_key,
            "user_id": user_id,
        }
        if attributes:
            payload.update(attributes)
        self.customer_links[f"{provider}:{customer_key}"] = payload


class NativeAuthFlowTests(unittest.TestCase):
    def test_email_signup_rejects_weak_password(self) -> None:
        repo = _FakeRepo()

        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="password",
                display_name="Native User",
            )

        self.assertEqual(raised.exception.code, "WEAK_PASSWORD")
        self.assertIn("uppercase", raised.exception.message.lower())
        self.assertEqual(repo.accounts, {})

    def test_email_signup_bootstraps_free_entitlement_before_confirmation(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            sign_up = native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )

        entitlement = repo.get_entitlement(sign_up["user"]["userId"])
        self.assertIsNotNone(entitlement)
        self.assertEqual(entitlement["plan_code"], "free")
        self.assertEqual(entitlement["status"], "active")

    def test_email_signup_uses_korean_template_when_locale_is_korean(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email") as send_email, mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
                locale="ko-KR",
            )

        self.assertEqual(send_email.call_count, 1)
        kwargs = send_email.call_args.kwargs
        self.assertEqual(kwargs.get("subject"), "Mixroom 계정 이메일 인증")
        self.assertIn("인증 코드는 123456", str(kwargs.get("text_body") or ""))

    def test_password_reset_uses_english_template_for_non_korean_locale(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        with mock.patch.object(native_auth, "send_auth_email") as send_email, mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="654321",
        ):
            native_auth.request_password_reset(
                repo,
                email="user@example.com",
                locale="ja-JP",
            )

        self.assertEqual(send_email.call_count, 1)
        kwargs = send_email.call_args.kwargs
        self.assertEqual(kwargs.get("subject"), "Reset your Mixroom password")
        self.assertIn(
            "Your Mixroom password reset code is 654321.",
            str(kwargs.get("text_body") or ""),
        )

    def test_email_signup_confirm_signin_refresh_and_signout_flow(self) -> None:
        repo = _FakeRepo()
        refresh_token_1 = "rt_session-1_secret"
        refresh_token_2 = "rt_session-2_secret"

        with mock.patch.object(native_auth, "send_auth_email") as send_email, mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            sign_up = native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
                given_name="Native",
                family_name="User",
                birthdate="2000-01-01",
            )
            self.assertEqual(send_email.call_count, 1)

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            side_effect=[
                (refresh_token_1, native_auth._hash_value(refresh_token_1)),  # noqa: SLF001
                (refresh_token_2, native_auth._hash_value(refresh_token_2)),  # noqa: SLF001
            ],
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=[
                "access-token-1",
                "id-token-1",
                "access-token-2",
                "id-token-2",
                "access-token-3",
                "id-token-3",
            ],
        ):
            confirm = native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )
            sign_in = native_auth.complete_password_sign_in(
                repo,
                identifier="user@example.com",
                password="CorrectHorseBatteryStaple1!",
            )
            refreshed = native_auth.refresh_session(
                repo,
                refresh_token=sign_in["tokens"]["refreshToken"],
            )

        self.assertTrue(sign_up["codeSent"])
        self.assertTrue(confirm["user"]["emailVerified"])
        self.assertEqual(repo.get_entitlement(confirm["user"]["userId"])["plan_code"], "free")
        self.assertEqual(sign_in["tokens"]["accessToken"], "access-token-2")
        self.assertEqual(refreshed["tokens"]["refreshToken"], refresh_token_2)
        self.assertEqual(len(repo.sessions), 2)
        for session in repo.sessions.values():
            self.assertEqual(str(session.get("expires_at") or "").strip(), "")
            self.assertNotIn("expires_at_ttl", session)
            self.assertTrue(str(session.get("last_refreshed_at") or "").strip())

        session_id = "session-2"
        sign_out = native_auth.sign_out_session(repo, session_id=session_id)
        self.assertTrue(sign_out["signedOut"])
        self.assertEqual(len(repo.sessions), 1)

    def test_resend_sign_up_code_invalidates_previous_code(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            side_effect=["123456", "654321"],
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            resent = native_auth.resend_email_verification_code(
                repo,
                email="user@example.com",
            )

        self.assertTrue(resent["resent"])
        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )
        self.assertEqual(raised.exception.code, "INVALID_VERIFICATION_CODE")

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-verified_secret",
                native_auth._hash_value("rt_session-verified_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token-verified", "id-token-verified"],
        ):
            confirmed = native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="654321",
            )

        self.assertTrue(confirmed["user"]["emailVerified"])

    def test_confirm_verified_email_requires_password_for_session(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-confirmed_secret",
                native_auth._hash_value("rt_session-confirmed_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token-confirmed", "id-token-confirmed"],
        ):
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        self.assertEqual(raised.exception.code, "ACCOUNT_ALREADY_VERIFIED")

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-retry_secret",
                native_auth._hash_value("rt_session-retry_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token-retry", "id-token-retry"],
        ):
            retried = native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
                password="CorrectHorseBatteryStaple1!",
            )

        self.assertEqual(retried["user"]["userId"], repo.get_auth_account_by_email("user@example.com")["user_id"])
        self.assertEqual(retried["tokens"]["accessToken"], "access-token-retry")

    def test_email_signup_returns_delivery_unavailable_when_email_send_fails(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailDeliveryError("ses unavailable"),
        ), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.register_email_account(
                    repo,
                    email="user@example.com",
                    password="CorrectHorseBatteryStaple1!",
                    display_name="Native User",
                )

        self.assertEqual(raised.exception.code, "EMAIL_DELIVERY_UNAVAILABLE")
        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(repo.accounts, {})
        self.assertEqual(repo.profiles, {})
        self.assertEqual(repo.entitlements, {})

    def test_email_signup_returns_suppressed_when_email_is_suppressed(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailSuppressedError(
                email="user@example.com",
                reason="BOUNCE",
            ),
        ), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.register_email_account(
                    repo,
                    email="user@example.com",
                    password="CorrectHorseBatteryStaple1!",
                    display_name="Native User",
                )

        self.assertEqual(raised.exception.code, "EMAIL_SUPPRESSED")
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.details.get("reason"), "BOUNCE")
        self.assertEqual(repo.accounts, {})
        self.assertEqual(repo.profiles, {})
        self.assertEqual(repo.entitlements, {})

    def test_resend_sign_up_code_restores_previous_code_when_email_send_fails(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            side_effect=["123456", "654321"],
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )

        original = repo.get_auth_account_by_email("user@example.com")
        self.assertIsNotNone(original)

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailDeliveryError("ses unavailable"),
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.resend_email_verification_code(
                    repo,
                    email="user@example.com",
                )

        self.assertEqual(raised.exception.code, "EMAIL_DELIVERY_UNAVAILABLE")
        restored = repo.get_auth_account_by_email("user@example.com")
        self.assertEqual(restored, original)

    def test_resend_sign_up_code_restores_previous_code_when_email_is_suppressed(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            side_effect=["123456", "654321"],
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )

        original = repo.get_auth_account_by_email("user@example.com")
        self.assertIsNotNone(original)

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailSuppressedError(
                email="user@example.com",
                reason="COMPLAINT",
            ),
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.resend_email_verification_code(
                    repo,
                    email="user@example.com",
                )

        self.assertEqual(raised.exception.code, "EMAIL_SUPPRESSED")
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.details.get("reason"), "COMPLAINT")
        restored = repo.get_auth_account_by_email("user@example.com")
        self.assertEqual(restored, original)

    def test_password_reset_request_restores_previous_code_when_email_send_fails(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        original = repo.get_auth_account_by_email("user@example.com")
        self.assertIsNotNone(original)

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailDeliveryError("ses unavailable"),
        ), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="654321",
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.request_password_reset(
                    repo,
                    email="user@example.com",
                )

        self.assertEqual(raised.exception.code, "EMAIL_DELIVERY_UNAVAILABLE")
        restored = repo.get_auth_account_by_email("user@example.com")
        self.assertEqual(restored, original)

    def test_password_reset_request_restores_previous_code_when_email_is_suppressed(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        original = repo.get_auth_account_by_email("user@example.com")
        self.assertIsNotNone(original)

        with mock.patch.object(
            native_auth,
            "send_auth_email",
            side_effect=native_auth.EmailSuppressedError(
                email="user@example.com",
                reason="BOUNCE",
            ),
        ), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="654321",
        ):
            with self.assertRaises(native_auth.AppUserAuthError) as raised:
                native_auth.request_password_reset(
                    repo,
                    email="user@example.com",
                )

        self.assertEqual(raised.exception.code, "EMAIL_SUPPRESSED")
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.details.get("reason"), "BOUNCE")
        restored = repo.get_auth_account_by_email("user@example.com")
        self.assertEqual(restored, original)

    def test_password_reset_rotates_password_and_clears_existing_sessions(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            side_effect=["123456", "654321"],
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )
            self.assertEqual(len(repo.sessions), 1)

            requested = native_auth.request_password_reset(
                repo,
                email="user@example.com",
            )

        self.assertTrue(requested["sent"])
        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.confirm_password_reset(
                repo,
                email="user@example.com",
                code="123456",
                new_password="NewCorrectHorseBatteryStaple1!",
            )
        self.assertEqual(raised.exception.code, "INVALID_RESET_CODE")

        reset = native_auth.confirm_password_reset(
            repo,
            email="user@example.com",
            code="654321",
            new_password="NewCorrectHorseBatteryStaple1!",
        )

        self.assertTrue(reset["reset"])
        self.assertEqual(len(repo.sessions), 0)

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-reset_secret",
                native_auth._hash_value("rt_session-reset_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token-reset", "id-token-reset"],
        ):
            sign_in = native_auth.complete_password_sign_in(
                repo,
                identifier="user@example.com",
                password="NewCorrectHorseBatteryStaple1!",
            )

        self.assertEqual(sign_in["tokens"]["accessToken"], "access-token-reset")

    def test_password_reset_rejects_weak_new_password(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            side_effect=["123456", "654321"],
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )
            native_auth.request_password_reset(
                repo,
                email="user@example.com",
            )

        original_account = repo.get_auth_account_by_email("user@example.com")
        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.confirm_password_reset(
                repo,
                email="user@example.com",
                code="654321",
                new_password="password",
            )

        self.assertEqual(raised.exception.code, "WEAK_PASSWORD")
        self.assertEqual(
            repo.get_auth_account_by_email("user@example.com"),
            original_account,
        )

    def test_refresh_session_reuses_stable_refresh_token(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )

        with mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-initial_secret",
                native_auth._hash_value("rt_session-initial_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=[
                "access-token-initial",
                "id-token-initial",
                "access-token-refresh-1",
                "id-token-refresh-1",
                "access-token-refresh-2",
                "id-token-refresh-2",
            ],
        ):
            confirmed = native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )
            refreshed_once = native_auth.refresh_session(
                repo,
                refresh_token=confirmed["tokens"]["refreshToken"],
            )
            refreshed_twice = native_auth.refresh_session(
                repo,
                refresh_token=confirmed["tokens"]["refreshToken"],
            )

        self.assertEqual(refreshed_once["tokens"]["refreshToken"], "rt_session-initial_secret")
        self.assertEqual(refreshed_twice["tokens"]["refreshToken"], "rt_session-initial_secret")
        self.assertEqual(refreshed_once["tokens"]["accessToken"], "access-token-refresh-1")
        self.assertEqual(refreshed_twice["tokens"]["accessToken"], "access-token-refresh-2")
        self.assertEqual(len(repo.sessions), 1)

    def test_legacy_cognito_password_sign_in_backfills_native_account(self) -> None:
        repo = _FakeRepo()
        repo.profiles["legacy-user"] = {
            "user_id": "legacy-user",
            "email": "legacy@example.com",
            "email_lc": "legacy@example.com",
            "display_name": "Legacy User",
            "auth_provider": "email",
            "created_at": "2026-03-13T00:00:00+00:00",
        }

        with mock.patch.object(
            native_auth,
            "sign_in_legacy_cognito_password",
            return_value={
                "sub": "legacy-user",
                "email": "legacy@example.com",
                "email_verified": "true",
                "cognito:username": "legacy@example.com",
                "name": "Legacy User",
            },
        ), mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-legacy_secret",
                native_auth._hash_value("rt_session-legacy_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token", "id-token"],
        ):
            result = native_auth.complete_password_sign_in(
                repo,
                identifier="legacy@example.com",
                password="CorrectHorseBatteryStaple1!",
            )

        account = repo.get_auth_account("legacy-user")
        self.assertIsNotNone(account)
        self.assertEqual(account["email"], "legacy@example.com")
        self.assertFalse(bool(account.get("legacy_cognito_enabled")))
        self.assertTrue(
            native_auth._verify_password(  # noqa: SLF001
                password="CorrectHorseBatteryStaple1!",
                salt=str(account.get("password_salt") or ""),
                expected_hash=str(account.get("password_hash") or ""),
            )
        )
        self.assertEqual(result["user"]["userId"], "legacy-user")
        self.assertEqual(repo.get_entitlement("legacy-user")["plan_code"], "free")
        self.assertEqual(len(repo.sessions), 1)

    def test_legacy_refresh_exchanges_cognito_session_into_native_session(self) -> None:
        repo = _FakeRepo()
        repo.profiles["legacy-user"] = {
            "user_id": "legacy-user",
            "email": "legacy@example.com",
            "email_lc": "legacy@example.com",
            "display_name": "Legacy User",
            "auth_provider": "email",
            "created_at": "2026-03-13T00:00:00+00:00",
        }

        with mock.patch.object(
            native_auth,
            "refresh_legacy_cognito_session",
            return_value={
                "sub": "legacy-user",
                "email": "legacy@example.com",
                "email_verified": "true",
                "cognito:username": "legacy@example.com",
                "name": "Legacy User",
            },
        ), mock.patch.object(
            native_auth,
            "new_refresh_token",
            return_value=(
                "rt_session-upgraded_secret",
                native_auth._hash_value("rt_session-upgraded_secret"),  # noqa: SLF001
            ),
        ), mock.patch.object(
            native_auth,
            "mint_token",
            side_effect=["access-token-upgraded", "id-token-upgraded"],
        ):
            result = native_auth.refresh_session(
                repo,
                refresh_token="legacy-refresh-token",
                fallback_token="",
            )

        self.assertEqual(result["user"]["userId"], "legacy-user")
        self.assertEqual(result["tokens"]["refreshToken"], "rt_session-upgraded_secret")
        self.assertEqual(len(repo.sessions), 1)

    def test_social_sign_in_reuses_existing_profile_user_id(self) -> None:
        repo = _FakeRepo()
        repo.profiles["legacy-social-user"] = {
            "user_id": "legacy-social-user",
            "email": "social@example.com",
            "email_lc": "social@example.com",
            "display_name": "Social User",
            "auth_provider": "google",
            "created_at": "2026-03-13T00:00:00+00:00",
        }

        result = native_auth.upsert_social_account(
            repo,
            provider="google",
            subject="google-subject-1",
            email="social@example.com",
            email_verified=True,
            display_name="Social User",
        )

        self.assertEqual(result["account"]["user_id"], "legacy-social-user")
        self.assertEqual(
            repo.get_customer_link("google", "auth:google-subject-1")["user_id"],
            "legacy-social-user",
        )
        self.assertEqual(repo.get_entitlement("legacy-social-user")["plan_code"], "free")

    def test_linked_social_sign_in_does_not_overwrite_email_owned_by_another_account(self) -> None:
        repo = _FakeRepo()
        repo.accounts["social-user"] = {
            "user_id": "social-user",
            "email": "social@example.com",
            "email_lc": "social@example.com",
            "auth_provider": "google",
            "email_verified": True,
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        repo.accounts_by_email["social@example.com"] = "social-user"
        repo.profiles["social-user"] = {
            "user_id": "social-user",
            "email": "social@example.com",
            "email_lc": "social@example.com",
            "display_name": "Social User",
            "auth_provider": "google",
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        repo.customer_links["google:auth:google-subject-1"] = {
            "provider": "google",
            "customer_key": "auth:google-subject-1",
            "user_id": "social-user",
        }
        repo.accounts["other-user"] = {
            "user_id": "other-user",
            "email": "taken@example.com",
            "email_lc": "taken@example.com",
            "auth_provider": "email",
            "email_verified": True,
            "created_at": "2026-03-13T00:00:00+00:00",
        }
        repo.accounts_by_email["taken@example.com"] = "other-user"

        result = native_auth.upsert_social_account(
            repo,
            provider="google",
            subject="google-subject-1",
            email="taken@example.com",
            email_verified=True,
            display_name="Social User",
        )

        self.assertEqual(result["account"]["user_id"], "social-user")
        self.assertEqual(result["account"]["email"], "social@example.com")
        self.assertEqual(repo.get_auth_account("social-user")["email"], "social@example.com")

    def test_change_password_rejects_weak_new_password(self) -> None:
        repo = _FakeRepo()

        with mock.patch.object(native_auth, "send_auth_email"), mock.patch.object(
            native_auth,
            "_generate_numeric_code",
            return_value="123456",
        ):
            native_auth.register_email_account(
                repo,
                email="user@example.com",
                password="CorrectHorseBatteryStaple1!",
                display_name="Native User",
            )
            native_auth.confirm_email_account(
                repo,
                email="user@example.com",
                code="123456",
            )

        account_before = repo.get_auth_account_by_email("user@example.com")
        with self.assertRaises(native_auth.AppUserAuthError) as raised:
            native_auth.change_password(
                repo,
                user_id=str(account_before["user_id"]),
                current_password="CorrectHorseBatteryStaple1!",
                new_password="password",
            )

        self.assertEqual(raised.exception.code, "WEAK_PASSWORD")
        self.assertEqual(
            repo.get_auth_account_by_email("user@example.com")["password_hash"],
            account_before["password_hash"],
        )


if __name__ == "__main__":
    unittest.main()
