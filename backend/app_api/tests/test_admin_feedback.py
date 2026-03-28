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
    "FEEDBACK_SUBMISSIONS_TABLE": "feedback-submissions",
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
    conditions_stub.Key = mock.Mock()
    sys.modules["boto3.dynamodb"] = dynamodb_stub
    sys.modules["boto3.dynamodb.conditions"] = conditions_stub

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
else:
    exceptions_stub = sys.modules["botocore.exceptions"]
    if not hasattr(exceptions_stub, "BotoCoreError"):
        class _BotoCoreError(Exception):
            pass

        exceptions_stub.BotoCoreError = _BotoCoreError

admin_module = importlib.import_module("src.handlers.api_admin_feedback")
feedback_repo_module = importlib.import_module("src.common.feedback_repository")


class _FakeRepo:
    def list_submissions(self, *, limit=50):
        return {
            "submissions": [
                {
                    "submission_id": "feedback_1",
                    "message_preview": "It broke",
                }
            ],
            "limit": limit,
            "has_more": True,
        }

    def get_submission(self, submission_id):
        if submission_id != "feedback_1":
            raise feedback_repo_module.FeedbackNotFoundError("Feedback submission not found.")
        return {
            "submission_id": submission_id,
            "message": "It broke",
            "source": "daw_chat",
            "allow_email_contact": True,
        }


class _FakeAccessRepo:
    def __init__(self, allowed_emails):
        self.allowed_emails = {email.strip().lower() for email in allowed_emails}

    def is_email_allowed(self, email):
        return email.strip().lower() in self.allowed_emails


class AdminFeedbackHandlerTests(unittest.TestCase):
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
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None, **kwargs: {
            "sub": user_id,
            "email": email,
        }
        admin_module.access_repo = _FakeAccessRepo({email})

    def test_requires_allowlisted_admin(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None, **kwargs: {
            "sub": "admin-user",
            "email": "blocked@example.com",
        }
        admin_module.access_repo = _FakeAccessRepo({"admin@example.com"})

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("allowlisted", result["body"])

    def test_lists_feedback_submissions(self):
        self._authenticate()
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/feedback",
                "requestContext": {"http": {"method": "GET"}},
                "queryStringParameters": {"limit": "10"},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"submission_id": "feedback_1"', result["body"])
        self.assertIn('"requested_email": "admin@example.com"', result["body"])
        self.assertIn('"has_more": true', result["body"])

    def test_returns_feedback_detail(self):
        self._authenticate()
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/feedback",
                "requestContext": {"http": {"method": "GET"}},
                "queryStringParameters": {"submission_id": "feedback_1"},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"source": "daw_chat"', result["body"])
        self.assertIn('"submission_id": "feedback_1"', result["body"])
        self.assertIn('"allow_email_contact": true', result["body"])


if __name__ == "__main__":
    unittest.main()
