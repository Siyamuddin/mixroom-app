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

admin_module = importlib.import_module("src.handlers.api_admin_overview")
overview_module = importlib.import_module("src.common.admin_overview_repository")


class _FakeRepo:
    def __init__(self, payload):
        self.payload = payload

    def build_overview(self):
        return dict(self.payload)


class _FakeAccessRepo:
    def __init__(self, allowed_emails):
        self.allowed_emails = {email.strip().lower() for email in allowed_emails}

    def is_email_allowed(self, email):
        return email.strip().lower() in self.allowed_emails


class AdminOverviewHandlerTests(unittest.TestCase):
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

    def test_requires_employee_sign_in(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = (
            lambda event, audiences=None, user_pool_ids=None: {}
        )

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 401)
        self.assertIn("Employee sign-in required", result["body"])

    def test_returns_not_found_when_admin_access_disabled(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = ""
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = ""
        admin_module.config.COGNITO_APP_CLIENT_ID = ""
        admin_module.config.COGNITO_USER_POOL_ID = ""

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 404)

    def test_rejects_non_allowlisted_email(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None: {
            "sub": "user-1",
            "email": "blocked@example.com",
        }
        admin_module.access_repo = _FakeAccessRepo({"allowed@example.com"})

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("allowlisted", result["body"])

    def test_returns_overview_payload(self):
        admin_module.config.ADMIN_COGNITO_APP_CLIENT_ID = "admin-client"
        admin_module.config.ADMIN_COGNITO_USER_POOL_ID = "admin-pool"
        admin_module.extract_claims_from_event = lambda event, audiences=None, user_pool_ids=None: {
            "sub": "admin-user",
            "email": "admin@example.com",
        }
        admin_module.access_repo = _FakeAccessRepo({"admin@example.com"})
        admin_module.repo = _FakeRepo(
            {
                "summary": {
                    "total_users": 2,
                    "tracked_projects": 1,
                },
                "users": [
                    {
                        "user_id": "user-1",
                        "email": "user@example.com",
                    }
                ],
            }
        )

        result = admin_module.handler({}, object())

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"requested_by": "admin-user"', result["body"])
        self.assertIn('"requested_email": "admin@example.com"', result["body"])
        self.assertIn('"total_users": 2', result["body"])


class AdminOverviewRepositoryTests(unittest.TestCase):
    def test_tier_breakdown_falls_back_to_scan_when_indexes_are_stale(self):
        repo = overview_module.AdminOverviewRepository.__new__(
            overview_module.AdminOverviewRepository
        )
        repo._entitlements = object()
        repo._count_entitlements = mock.Mock(return_value=0)
        repo._describe_item_count = mock.Mock(return_value=5)
        repo._scan_tier_breakdown = mock.Mock(
            return_value=[
                {"tier": "free", "user_count": 5, "active_user_count": 5},
                {"tier": "pro", "user_count": 0, "active_user_count": 0},
                {"tier": "studio", "user_count": 0, "active_user_count": 0},
            ]
        )
        warnings: list[str] = []

        result = overview_module.AdminOverviewRepository._build_tier_breakdown_fast(
            repo,
            warnings,
        )

        self.assertEqual(result[0]["user_count"], 5)
        repo._scan_tier_breakdown.assert_called_once()
        self.assertIn("entitlement_index_stale:indexed=0:table=5", warnings)

    def test_tier_breakdown_keeps_index_path_when_counts_match(self):
        repo = overview_module.AdminOverviewRepository.__new__(
            overview_module.AdminOverviewRepository
        )
        repo._entitlements = object()
        repo._count_entitlements = mock.Mock(
            side_effect=[5, 5, 0, 0, 0, 0]
        )
        repo._describe_item_count = mock.Mock(return_value=5)
        repo._scan_tier_breakdown = mock.Mock()
        warnings: list[str] = []

        result = overview_module.AdminOverviewRepository._build_tier_breakdown_fast(
            repo,
            warnings,
        )

        self.assertEqual(result[0]["tier"], "free")
        self.assertEqual(result[0]["user_count"], 5)
        repo._scan_tier_breakdown.assert_not_called()
        self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
