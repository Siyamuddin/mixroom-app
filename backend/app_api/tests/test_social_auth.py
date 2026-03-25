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
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
    "APP_AUTH_SECRET_ARN": "app-auth-secret",
    "SOCIAL_AUTH_SECRET_ARN": "social-auth-secret",
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

if "jwt" not in sys.modules:
    jwt_stub = ModuleType("jwt")
    jwt_stub.get_unverified_header = mock.Mock(return_value={})
    jwt_stub.decode = mock.Mock(return_value={})
    jwt_stub.algorithms = SimpleNamespace(
        RSAAlgorithm=SimpleNamespace(from_jwk=mock.Mock(return_value=object()))
    )
    sys.modules["jwt"] = jwt_stub

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

if "google" not in sys.modules:
    google_stub = ModuleType("google")
    auth_stub = ModuleType("google.auth")
    transport_stub = ModuleType("google.auth.transport")
    requests_stub = ModuleType("google.auth.transport.requests")
    requests_stub.Request = mock.Mock(return_value=object())
    oauth2_stub = ModuleType("google.oauth2")
    id_token_stub = ModuleType("google.oauth2.id_token")
    id_token_stub.verify_oauth2_token = mock.Mock(return_value={})

    google_stub.auth = auth_stub
    google_stub.oauth2 = oauth2_stub
    auth_stub.transport = transport_stub
    transport_stub.requests = requests_stub
    oauth2_stub.id_token = id_token_stub

    sys.modules["google"] = google_stub
    sys.modules["google.auth"] = auth_stub
    sys.modules["google.auth.transport"] = transport_stub
    sys.modules["google.auth.transport.requests"] = requests_stub
    sys.modules["google.oauth2"] = oauth2_stub
    sys.modules["google.oauth2.id_token"] = id_token_stub

from src.common import native_auth, social_auth  # noqa: E402


class CompleteSocialSignInTests(unittest.TestCase):
    def test_verify_google_identity_accepts_allowed_audience(self) -> None:
        claims = {
            "aud": "ios-client-id.apps.googleusercontent.com",
            "sub": "google-subject",
            "email": "user@example.com",
            "email_verified": True,
            "name": "Google User",
        }

        with mock.patch.object(
            social_auth.google_id_token,
            "verify_oauth2_token",
            return_value=claims,
        ), mock.patch.object(
            social_auth.config,
            "GOOGLE_OAUTH_CLIENT_IDS",
            ["ios-client-id.apps.googleusercontent.com"],
        ):
            identity = social_auth._verify_google_identity(  # noqa: SLF001
                {"id_token": "token", "display_name": "Fallback Name"}
            )

        self.assertEqual(identity.provider, "google")
        self.assertEqual(identity.subject, "google-subject")
        self.assertEqual(identity.email, "user@example.com")
        self.assertEqual(identity.display_name, "Google User")

    def test_verify_google_identity_accepts_allowed_authorized_party(self) -> None:
        claims = {
            "aud": "ios-client-id.apps.googleusercontent.com",
            "azp": "web-client-id.apps.googleusercontent.com",
            "sub": "google-subject",
            "email": "user@example.com",
            "email_verified": True,
            "name": "Google User",
        }

        with mock.patch.object(
            social_auth.google_id_token,
            "verify_oauth2_token",
            return_value=claims,
        ), mock.patch.object(
            social_auth.config,
            "GOOGLE_OAUTH_CLIENT_IDS",
            ["web-client-id.apps.googleusercontent.com"],
        ):
            identity = social_auth._verify_google_identity({"id_token": "token"})  # noqa: SLF001

        self.assertEqual(identity.provider, "google")
        self.assertEqual(identity.subject, "google-subject")
        self.assertEqual(identity.email, "user@example.com")

    def test_complete_social_sign_in_returns_native_session(self) -> None:
        identity = social_auth.SocialIdentity(
            provider="google",
            subject="google-subject-123",
            email="hello@example.com",
            email_verified=True,
            display_name="Hello User",
        )

        with mock.patch.object(
            social_auth, "_verify_google_identity", return_value=identity
        ), mock.patch.object(
            social_auth,
            "upsert_social_account",
            return_value={
                "requiresSignupCompletion": True,
                "account": {
                    "user_id": "user-123",
                    "email": "hello@example.com",
                    "auth_provider": "google",
                    "email_verified": True,
                    "created_at": "2026-03-13T00:00:00+00:00",
                },
                "profile": {
                    "user_id": "user-123",
                    "email": "hello@example.com",
                    "display_name": "Hello User",
                    "created_at": "2026-03-13T00:00:00+00:00",
                },
            },
        ), mock.patch.object(
            social_auth,
            "issue_session",
            return_value={
                "tokens": {
                    "accessToken": "access-token",
                    "idToken": "id-token",
                    "refreshToken": "refresh-token",
                    "expiresAtUtc": "2026-03-13T01:00:00+00:00",
                },
                "user": {
                    "userId": "user-123",
                    "email": "hello@example.com",
                    "displayName": "Hello User",
                    "provider": "google",
                    "emailVerified": True,
                    "createdAt": "2026-03-13T00:00:00+00:00",
                },
            },
        ):
            result = social_auth.complete_social_sign_in(
                "google", {"provider": "google"}
            )

        self.assertEqual(result["user"]["email"], "hello@example.com")
        self.assertTrue(result["requiresSignupCompletion"])
        self.assertEqual(result["tokens"]["accessToken"], "access-token")

    def test_complete_social_sign_in_wraps_native_conflicts(self) -> None:
        identity = social_auth.SocialIdentity(
            provider="google",
            subject="google-subject-999",
            email="taken@example.com",
            email_verified=True,
            display_name="Taken User",
        )

        with mock.patch.object(
            social_auth, "_verify_google_identity", return_value=identity
        ), mock.patch.object(
            social_auth,
            "upsert_social_account",
            side_effect=native_auth.AppUserAuthError(
                "Mixroom already has an account for taken@example.com.",
                code="AUTH_METHOD_CONFLICT",
                status_code=409,
                details={
                    "email": "taken@example.com",
                    "existing_provider": "email",
                    "existing_provider_label": "Email",
                    "verification_required": False,
                    "password_reset_available": True,
                    "suggested_action": "use_email",
                },
            ),
        ):
            with self.assertRaises(social_auth.SocialAuthError) as raised:
                social_auth.complete_social_sign_in("google", {"provider": "google"})

        error = raised.exception
        self.assertEqual(error.code, "AUTH_METHOD_CONFLICT")
        self.assertEqual(error.status_code, 409)
        self.assertEqual(error.details.get("existing_provider"), "email")

    def test_verify_apple_identity_accepts_matching_nonce(self) -> None:
        claims = {
            "sub": "apple-subject",
            "email": "user@example.com",
            "email_verified": True,
            "nonce": "nonce-123",
        }

        with mock.patch.object(
            social_auth.config,
            "APPLE_BUNDLE_ID",
            "com.mixroom.mixroomapp",
        ), mock.patch.object(
            social_auth.jwt,
            "get_unverified_header",
            return_value={"kid": "kid-1"},
        ), mock.patch.object(
            social_auth,
            "_apple_signing_key",
            return_value=object(),
        ), mock.patch.object(
            social_auth.jwt,
            "decode",
            return_value=claims,
        ):
            identity = social_auth._verify_apple_identity(  # noqa: SLF001
                {
                    "id_token": "token",
                    "nonce": "nonce-123",
                }
            )

        self.assertEqual(identity.provider, "apple")
        self.assertEqual(identity.subject, "apple-subject")
        self.assertEqual(identity.email, "user@example.com")

    def test_verify_apple_identity_rejects_mismatched_nonce(self) -> None:
        claims = {
            "sub": "apple-subject",
            "email": "user@example.com",
            "email_verified": True,
            "nonce": "unexpected",
        }

        with mock.patch.object(
            social_auth.config,
            "APPLE_BUNDLE_ID",
            "com.mixroom.mixroomapp",
        ), mock.patch.object(
            social_auth.jwt,
            "get_unverified_header",
            return_value={"kid": "kid-1"},
        ), mock.patch.object(
            social_auth,
            "_apple_signing_key",
            return_value=object(),
        ), mock.patch.object(
            social_auth.jwt,
            "decode",
            return_value=claims,
        ):
            with self.assertRaisesRegex(ValueError, "nonce is invalid"):
                social_auth._verify_apple_identity(  # noqa: SLF001
                    {
                        "id_token": "token",
                        "nonce": "nonce-123",
                    }
                )


if __name__ == "__main__":
    unittest.main()
