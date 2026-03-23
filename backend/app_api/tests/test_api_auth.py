import importlib
import json
import os
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))
sys.path.insert(0, str(_ROOT / "src"))

_REQUIRED_ENV = {
    "BILLING_EVENTS_TABLE": "billing-events",
    "SUBSCRIPTIONS_TABLE": "subscriptions",
    "ENTITLEMENTS_TABLE": "entitlements",
    "USERS_TABLE": "users",
    "USERNAME_CLAIMS_TABLE": "username-claims",
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
}
for key, value in _REQUIRED_ENV.items():
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

if "jwt" not in sys.modules:
    jwt_stub = ModuleType("jwt")
    jwt_stub.decode = mock.Mock(return_value={})
    jwt_stub.get_unverified_header = mock.Mock(return_value={})
    sys.modules["jwt"] = jwt_stub

if "google.auth.transport.requests" not in sys.modules:
    google_stub = ModuleType("google")
    auth_stub = ModuleType("google.auth")
    transport_stub = ModuleType("google.auth.transport")
    requests_stub = ModuleType("google.auth.transport.requests")
    requests_stub.Request = mock.Mock(return_value=mock.Mock())
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

module = importlib.import_module("src.handlers.api_auth")


class ApiAuthHandlerTests(unittest.TestCase):
    def setUp(self):
        self.original_rate_limiter = module.rate_limiter
        self.original_register_email_account = module.register_email_account

    def tearDown(self):
        module.rate_limiter = self.original_rate_limiter
        module.register_email_account = self.original_register_email_account

    def test_sign_up_returns_429_when_rate_limited(self):
        module.rate_limiter = mock.Mock()

        class _Decision:
            def __init__(self, allowed, retry_after_seconds, reason):
                self.allowed = allowed
                self.retry_after_seconds = retry_after_seconds
                self.reason = reason

        module.rate_limiter.enforce.side_effect = [
            _Decision(False, 9, "blocked"),
            _Decision(True, 0, ""),
        ]

        response = module.handler(
            {
                "rawPath": "/v1/auth/sign-up",
                "requestContext": {"http": {"method": "POST", "sourceIp": "1.2.3.4"}},
                "body": json.dumps(
                    {
                        "email": "user@example.com",
                        "password": "CorrectHorseBatteryStaple1!",
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 429)
        self.assertEqual(response["headers"]["Retry-After"], "9")
        self.assertIn('"code": "RATE_LIMITED"', response["body"])

    def test_sign_up_calls_registration_when_not_rate_limited(self):
        class _Decision:
            def __init__(self, allowed, retry_after_seconds=0, reason=""):
                self.allowed = allowed
                self.retry_after_seconds = retry_after_seconds
                self.reason = reason

        module.rate_limiter = mock.Mock()
        module.rate_limiter.enforce.side_effect = [
            _Decision(True),
            _Decision(True),
        ]
        module.register_email_account = mock.Mock(
            return_value={"user": {"userId": "user-1"}, "codeSent": True}
        )

        response = module.handler(
            {
                "rawPath": "/v1/auth/sign-up",
                "requestContext": {"http": {"method": "POST", "sourceIp": "1.2.3.4"}},
                "body": json.dumps(
                    {
                        "email": "user@example.com",
                        "password": "CorrectHorseBatteryStaple1!",
                    }
                ),
            },
            object(),
        )

        self.assertEqual(response["statusCode"], 200)
        module.register_email_account.assert_called_once()


if __name__ == "__main__":
    unittest.main()
