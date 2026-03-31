import importlib
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
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
    "COGNITO_USER_POOL_ID": "pool-id",
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

if "botocore.exceptions" not in sys.modules:
    botocore_stub = ModuleType("botocore")
    exceptions_stub = ModuleType("botocore.exceptions")

    class _ClientError(Exception):
        def __init__(self, response: dict, operation_name: str = "") -> None:
            super().__init__(operation_name)
            self.response = response

    class _BotoCoreError(Exception):
        pass

    exceptions_stub.ClientError = _ClientError
    exceptions_stub.BotoCoreError = _BotoCoreError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub

admin_module = importlib.import_module(
    "src.handlers.api_admin_producer_capture_whitelist"
)


class _FakeRepo:
    def __init__(self) -> None:
        self.get_calls = 0
        self.update_calls = []
        self.get_payload = {
            "usernames": ["lavitababy1004", "andrewtest"],
            "source": "default",
            "configurable": True,
        }
        self.update_payload = {
            "usernames": ["lavitababy1004", "andrewtest", "anotheruser"],
            "source": "remote",
            "configurable": True,
            "updated_by_email": "admin@example.com",
        }

    def get_whitelist_settings(self):
        self.get_calls += 1
        return dict(self.get_payload)

    def update_whitelist_settings(
        self,
        *,
        usernames,
        updated_by_user_id,
        updated_by_email,
    ):
        self.update_calls.append(
            {
                "usernames": usernames,
                "updated_by_user_id": updated_by_user_id,
                "updated_by_email": updated_by_email,
            }
        )
        return dict(self.update_payload)


class _FakeAccessRepo:
    def __init__(self, allowed_emails):
        self.allowed_emails = {email.strip().lower() for email in allowed_emails}

    def is_email_allowed(self, email):
        return email.strip().lower() in self.allowed_emails


class AdminProducerCaptureWhitelistHandlerTests(unittest.TestCase):
    def setUp(self):
        self._original_repo = admin_module.repo
        self._original_access_repo = admin_module.access_repo
        self._original_admin_client_id = admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID
        self._original_admin_pool_id = admin_module.config.ADMIN_COGNITO_USER_POOL_ID
        self._original_cognito_client_id = admin_module.config.COGNITO_APP_CLIENT_ID
        self._original_cognito_pool_id = admin_module.config.COGNITO_USER_POOL_ID
        self._original_extract_claims = admin_module.extract_claims_from_event

    def tearDown(self):
        admin_module.repo = self._original_repo
        admin_module.access_repo = self._original_access_repo
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = self._original_admin_client_id
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = self._original_admin_pool_id
        admin_module.config.COGNITO_APP_CLIENT_ID = self._original_cognito_client_id
        admin_module.config.COGNITO_USER_POOL_ID = self._original_cognito_pool_id
        admin_module.extract_claims_from_event = self._original_extract_claims

    def _authenticate(self, email="admin@example.com", user_id="admin-user"):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None: {
            "sub": user_id,
            "email": email,
        }
        admin_module.access_repo = _FakeAccessRepo({email})

    def test_returns_whitelist_settings(self):
        self._authenticate()
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/producer-capture-whitelist",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"can_edit": true', result["body"])
        self.assertIn('"lavitababy1004"', result["body"])
        self.assertIn('"requested_email": "admin@example.com"', result["body"])

    def test_updates_whitelist_settings(self):
        self._authenticate()
        repo = _FakeRepo()
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/producer-capture-whitelist",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"usernames":["lavitababy1004","andrewtest","anotheruser"]}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(
            repo.update_calls[0]["usernames"],
            ["lavitababy1004", "andrewtest", "anotheruser"],
        )
        self.assertEqual(repo.update_calls[0]["updated_by_email"], "admin@example.com")

    def test_requires_allowlisted_admin_email(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None: {
            "sub": "admin-user",
            "email": "blocked@example.com",
        }
        admin_module.access_repo = _FakeAccessRepo({"admin@example.com"})
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/producer-capture-whitelist",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("allowlisted", result["body"])


if __name__ == "__main__":
    unittest.main()
