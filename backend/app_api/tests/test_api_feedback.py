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
    "USERS_TABLE": "users",
    "USERNAME_CLAIMS_TABLE": "username-claims",
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
    "AUTH_RATE_LIMITS_TABLE": "auth-rate-limits",
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
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

    class _BotoCoreError(Exception):
        pass

    exceptions_stub.ClientError = _ClientError
    exceptions_stub.BotoCoreError = _BotoCoreError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub

feedback_module = importlib.import_module("src.handlers.api_feedback")
feedback_repo_module = importlib.import_module("src.common.feedback_repository")


class _FakeDecision:
    def __init__(self, allowed=True, retry_after_seconds=0):
        self.allowed = allowed
        self.retry_after_seconds = retry_after_seconds


class _FakeRateLimiter:
    def __init__(self, decisions=None):
        self.decisions = list(decisions or [])
        self.calls = []

    def enforce(self, **kwargs):
        self.calls.append(kwargs)
        if self.decisions:
            return self.decisions.pop(0)
        return _FakeDecision()


class _FakeRepo:
    def __init__(self):
        self.create_calls = []
        self.error = None

    def create_submission(self, *, user_id, claims, payload):
        self.create_calls.append(
            {
                "user_id": user_id,
                "claims": dict(claims),
                "payload": dict(payload),
            }
        )
        if self.error is not None:
            raise self.error
        return {
            "submission_id": "feedback_123",
            "created_at": "2026-03-23T00:00:00+00:00",
        }


class FeedbackApiHandlerTests(unittest.TestCase):
    def setUp(self):
        self._original_repo = feedback_module.repo
        self._original_rate_limiter = feedback_module.rate_limiter
        self._original_extract_claims = feedback_module.extract_claims_from_event
        self._original_table_name = feedback_module.config.FEEDBACK_SUBMISSIONS_TABLE
        feedback_module.config.FEEDBACK_SUBMISSIONS_TABLE = "feedback-submissions"

    def tearDown(self):
        feedback_module.repo = self._original_repo
        feedback_module.rate_limiter = self._original_rate_limiter
        feedback_module.extract_claims_from_event = self._original_extract_claims
        feedback_module.config.FEEDBACK_SUBMISSIONS_TABLE = self._original_table_name

    def test_submit_feedback_returns_thank_you(self):
        repo = _FakeRepo()
        feedback_module.repo = repo
        feedback_module.rate_limiter = _FakeRateLimiter()
        feedback_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
        }

        result = feedback_module.handler(
            {
                "rawPath": "/v1/feedback",
                "requestContext": {"http": {"method": "POST", "sourceIp": "1.2.3.4"}},
                "body": (
                    '{"category":"feedback","source":"home","message":"Love the app","allow_email_contact":true}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn("Thank you for your submission!", result["body"])
        self.assertEqual(repo.create_calls[0]["payload"]["source"], "home")
        self.assertTrue(repo.create_calls[0]["payload"]["allow_email_contact"])

    def test_submit_feedback_returns_429_when_rate_limited(self):
        feedback_module.repo = _FakeRepo()
        feedback_module.rate_limiter = _FakeRateLimiter(
            decisions=[_FakeDecision(allowed=False, retry_after_seconds=45)]
        )
        feedback_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
        }

        result = feedback_module.handler(
            {
                "rawPath": "/v1/feedback",
                "requestContext": {"http": {"method": "POST", "sourceIp": "1.2.3.4"}},
                "body": (
                    '{"category":"feedback","source":"home","message":"Love the app"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 429)
        self.assertEqual(result["headers"]["Retry-After"], "45")
        self.assertIn('"code": "RATE_LIMITED"', result["body"])

    def test_submit_feedback_returns_validation_error(self):
        repo = _FakeRepo()
        repo.error = ValueError("Feedback message cannot be empty.")
        feedback_module.repo = repo
        feedback_module.rate_limiter = _FakeRateLimiter()
        feedback_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
        }

        result = feedback_module.handler(
            {
                "rawPath": "/v1/feedback",
                "requestContext": {"http": {"method": "POST", "sourceIp": "1.2.3.4"}},
                "body": '{"category":"feedback","source":"home","message":"   "}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("cannot be empty", result["body"])


class FeedbackSanitizerTests(unittest.TestCase):
    def test_sanitize_feedback_text_strips_control_chars_and_trims(self):
        value = feedback_repo_module.sanitize_feedback_text(
            "  Hello\x00 there \r\n\r\n this\t\tworks  "
        )

        self.assertEqual(value, "Hello there\n\nthis works")


if __name__ == "__main__":
    unittest.main()
