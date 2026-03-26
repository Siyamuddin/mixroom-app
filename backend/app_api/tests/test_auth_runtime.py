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

from src.common import auth as auth_module  # noqa: E402


class _FakeRepo:
    def __init__(self) -> None:
        self.sessions = {}
        self.accounts = {}

    def get_auth_session(self, session_id):
        session = self.sessions.get(session_id)
        return dict(session) if session else None

    def delete_auth_session(self, session_id):
        self.sessions.pop(session_id, None)

    def get_auth_account(self, user_id):
        account = self.accounts.get(user_id)
        return dict(account) if account else None


class AuthRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_repo = auth_module._repo
        self.original_app_auth_secret = auth_module.config.APP_AUTH_SECRET_ARN
        self.original_region = auth_module.config.COGNITO_REGION
        self.original_pool_id = auth_module.config.COGNITO_USER_POOL_ID
        self.original_client_id = auth_module.config.COGNITO_APP_CLIENT_ID
        auth_module.config.APP_AUTH_SECRET_ARN = "app-auth-secret"
        auth_module.config.COGNITO_REGION = "ap-northeast-2"
        auth_module.config.COGNITO_USER_POOL_ID = "pool-id"
        auth_module.config.COGNITO_APP_CLIENT_ID = "client-id"

    def tearDown(self) -> None:
        auth_module._repo = self.original_repo
        auth_module.config.APP_AUTH_SECRET_ARN = self.original_app_auth_secret
        auth_module.config.COGNITO_REGION = self.original_region
        auth_module.config.COGNITO_USER_POOL_ID = self.original_pool_id
        auth_module.config.COGNITO_APP_CLIENT_ID = self.original_client_id

    def test_extract_claims_requires_live_native_session(self) -> None:
        repo = _FakeRepo()
        repo.sessions["session-1"] = {
            "session_id": "session-1",
            "user_id": "user-1",
        }
        repo.accounts["user-1"] = {"user_id": "user-1"}
        auth_module._repo = repo

        with mock.patch.object(
            auth_module,
            "verify_token",
            return_value={"sub": "user-1", "sid": "session-1", "token_use": "access"},
        ):
            claims = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": "Bearer native-token"}},
                allow_native=True,
            )

        self.assertEqual(claims["sub"], "user-1")

    def test_extract_claims_accepts_native_session_without_expiry(self) -> None:
        repo = _FakeRepo()
        repo.sessions["session-1"] = {
            "session_id": "session-1",
            "user_id": "user-1",
            "created_at": "2026-03-26T00:00:00+00:00",
        }
        repo.accounts["user-1"] = {"user_id": "user-1"}
        auth_module._repo = repo

        with mock.patch.object(
            auth_module,
            "verify_token",
            return_value={"sub": "user-1", "sid": "session-1", "token_use": "access"},
        ):
            claims = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": "Bearer native-token"}},
                allow_native=True,
            )

        self.assertEqual(claims["sub"], "user-1")

    def test_extract_claims_rejects_revoked_native_session(self) -> None:
        repo = _FakeRepo()
        repo.accounts["user-1"] = {"user_id": "user-1"}
        auth_module._repo = repo

        with mock.patch.object(
            auth_module,
            "verify_token",
            return_value={"sub": "user-1", "sid": "missing-session", "token_use": "access"},
        ):
            claims = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": "Bearer native-token"}},
                allow_native=True,
            )

        self.assertEqual(claims, {})

    def test_extract_claims_only_accepts_cognito_when_explicitly_enabled(self) -> None:
        with mock.patch.object(
            auth_module,
            "verify_cognito_token",
            return_value={"sub": "legacy-user"},
        ):
            blocked = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": "Bearer cognito-token"}},
                allow_native=False,
            )
            allowed = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": "Bearer cognito-token"}},
                allow_native=False,
                allow_cognito=True,
            )

        self.assertEqual(blocked, {})
        self.assertEqual(allowed["sub"], "legacy-user")

    def test_authorizer_claims_reject_native_source_when_native_not_allowed(self) -> None:
        claims = auth_module.extract_claims_from_event(
            {
                "requestContext": {
                    "authorizer": {
                        "jwt": {
                            "claims": {
                                "iss": auth_module.config.APP_AUTH_ISSUER,
                                "aud": auth_module.config.APP_AUTH_AUDIENCE,
                                "sub": "user-1",
                                "sid": "session-1",
                                "token_use": "access",
                            }
                        }
                    }
                }
            },
            allow_native=False,
            allow_cognito=True,
        )

        self.assertEqual(claims, {})

    def test_authorizer_claims_accept_matching_cognito_source(self) -> None:
        claims = auth_module.extract_claims_from_event(
            {
                "requestContext": {
                    "authorizer": {
                        "jwt": {
                            "claims": {
                                "iss": "https://cognito-idp.ap-northeast-2.amazonaws.com/pool-id",
                                "client_id": "client-id",
                                "sub": "legacy-user",
                                "token_use": "access",
                            }
                        }
                    }
                }
            },
            allow_native=False,
            allow_cognito=True,
        )

        self.assertEqual(claims["sub"], "legacy-user")


if __name__ == "__main__":
    unittest.main()
