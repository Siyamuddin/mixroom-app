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

admin_module = importlib.import_module("src.handlers.api_admin_ai_prompt_limits")


class _FakeRepo:
    def __init__(self) -> None:
        self.get_calls = 0
        self.update_calls = []
        self.get_payload = {
            "free_daily_prompt_limit": 200,
            "free_weekly_prompt_limit": 600,
            "source": "default",
            "configurable": True,
        }
        self.update_payload = {
            "free_daily_prompt_limit": 200,
            "free_weekly_prompt_limit": 600,
            "source": "remote",
            "configurable": True,
            "updated_by_email": "admin@example.com",
        }

    def get_prompt_limits(self):
        self.get_calls += 1
        return dict(self.get_payload)

    def update_prompt_limits(
        self,
        *,
        free_daily_prompt_limit,
        free_weekly_prompt_limit,
        updated_by_user_id,
        updated_by_email,
    ):
        self.update_calls.append(
            {
                "free_daily_prompt_limit": free_daily_prompt_limit,
                "free_weekly_prompt_limit": free_weekly_prompt_limit,
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


class AdminAiPromptLimitsHandlerTests(unittest.TestCase):
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

    def test_requires_employee_sign_in(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = (
            lambda event, audiences=None, user_pool_ids=None: {}
        )

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 401)
        self.assertIn("Employee sign-in required", result["body"])

    def test_returns_current_prompt_limits(self):
        self._authenticate()
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-prompt-limits",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"requested_email": "admin@example.com"', result["body"])
        self.assertIn('"free_daily_prompt_limit": 200', result["body"])
        self.assertIn('"can_edit": false', result["body"])

    def test_updates_prompt_limits(self):
        self._authenticate(email="andrew@mixroom.ai")
        repo = _FakeRepo()
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-prompt-limits",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"free_daily_prompt_limit":200,"free_weekly_prompt_limit":600}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(repo.update_calls[0]["free_daily_prompt_limit"], 200)
        self.assertEqual(repo.update_calls[0]["free_weekly_prompt_limit"], 600)
        self.assertEqual(repo.update_calls[0]["updated_by_email"], "andrew@mixroom.ai")

    def test_update_requires_ai_editor_email(self):
        self._authenticate(email="other-admin@example.com")
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-prompt-limits",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"free_daily_prompt_limit":200,"free_weekly_prompt_limit":600}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("andrew@mixroom.ai", result["body"])


if __name__ == "__main__":
    unittest.main()
