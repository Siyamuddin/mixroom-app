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
    "CATALOG_MAPPINGS_TABLE": "catalog-mappings",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconcile-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
    "USER_TOMBSTONES_TABLE": "user-tombstones",
    "ADMIN_ENTITLEMENT_OVERRIDES_TABLE": "admin-entitlement-overrides",
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
    conditions_stub.Attr = mock.Mock()
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

admin_module = importlib.import_module("src.handlers.api_admin_users")
repo_module = importlib.import_module("src.common.admin_user_repository")


class _FakeRepo:
    def __init__(
        self,
        search_payload=None,
        create_payload=None,
        delete_payload=None,
        grant_payload=None,
        override_payload=None,
    ):
        self.search_payload = search_payload or {"users": []}
        self.create_payload = create_payload or {"created": True}
        self.delete_payload = delete_payload or {"deleted": True}
        self.grant_payload = grant_payload or {"granted": True}
        self.override_payload = override_payload or {"overridden": True}
        self.search_calls = []
        self.create_calls = []
        self.delete_calls = []
        self.grant_calls = []
        self.override_calls = []
        self.create_error = None
        self.delete_error = None
        self.grant_error = None
        self.override_error = None

    def search_users(self, *, query="", limit=24, subscription_filter="all"):
        self.search_calls.append(
            {
                "query": query,
                "limit": limit,
                "subscription_filter": subscription_filter,
            }
        )
        return dict(self.search_payload)

    def create_username_account(
        self,
        *,
        username: str,
        display_name: str,
        password: str,
        email: str = "",
        created_by_user_id: str,
        created_by_email: str,
    ):
        self.create_calls.append(
            {
                "username": username,
                "display_name": display_name,
                "password": password,
                "email": email,
                "created_by_user_id": created_by_user_id,
                "created_by_email": created_by_email,
            }
        )
        if self.create_error is not None:
            raise self.create_error
        return dict(self.create_payload)

    def delete_user(
        self,
        *,
        user_id: str,
        deleted_by_user_id: str,
        deleted_by_email: str,
        reason: str,
        confirm_email: str,
        force: bool = False,
    ):
        self.delete_calls.append(
            {
                "user_id": user_id,
                "deleted_by_user_id": deleted_by_user_id,
                "deleted_by_email": deleted_by_email,
                "reason": reason,
                "confirm_email": confirm_email,
                "force": force,
            }
        )
        if self.delete_error is not None:
            raise self.delete_error
        return dict(self.delete_payload)

    def grant_prompt_allowance(
        self,
        *,
        user_id: str,
        prompt_count: int,
        granted_by_user_id: str,
        granted_by_email: str,
    ):
        self.grant_calls.append(
            {
                "user_id": user_id,
                "prompt_count": prompt_count,
                "granted_by_user_id": granted_by_user_id,
                "granted_by_email": granted_by_email,
            }
        )
        if self.grant_error is not None:
            raise self.grant_error
        return dict(self.grant_payload)

    def apply_entitlement_override(
        self,
        *,
        user_id: str,
        plan_code: str,
        expires_at: str,
        reason: str,
        confirm_identifier: str,
        confirm_admin_first_name: str,
        granted_by_user_id: str,
        granted_by_email: str,
        seat_limit=None,
        organization_name: str = "",
    ):
        self.override_calls.append(
            {
                "user_id": user_id,
                "plan_code": plan_code,
                "expires_at": expires_at,
                "reason": reason,
                "confirm_identifier": confirm_identifier,
                "confirm_admin_first_name": confirm_admin_first_name,
                "granted_by_user_id": granted_by_user_id,
                "granted_by_email": granted_by_email,
                "seat_limit": seat_limit,
                "organization_name": organization_name,
            }
        )
        if self.override_error is not None:
            raise self.override_error
        return dict(self.override_payload)


class _FakeAccessRepo:
    def __init__(self, allowed_emails):
        self.allowed_emails = {email.strip().lower() for email in allowed_emails}

    def is_email_allowed(self, email):
        return email.strip().lower() in self.allowed_emails


class AdminUsersHandlerTests(unittest.TestCase):
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

    def test_returns_search_results(self):
        self._authenticate()
        admin_module.repo = _FakeRepo(
            search_payload={
                "users": [{"user_id": "user-1", "email": "user@example.com"}],
                "total_matches": 1,
            }
        )

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users",
                "requestContext": {"http": {"method": "GET"}},
                "queryStringParameters": {
                    "query": "user",
                    "limit": "10",
                    "subscription_filter": "paying",
                },
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"requested_email": "admin@example.com"', result["body"])
        self.assertIn('"total_matches": 1', result["body"])
        self.assertEqual(admin_module.repo.search_calls[0]["query"], "user")
        self.assertEqual(
            admin_module.repo.search_calls[0]["subscription_filter"],
            "paying",
        )

    def test_create_username_account_returns_payload(self):
        self._authenticate()
        admin_module.repo = _FakeRepo(
            create_payload={
                "created": True,
                "user_id": "user-1",
                "username": "student_1",
                "email": "student@example.com",
                "user": {
                    "user_id": "user-1",
                    "username": "student_1",
                    "email": "student@example.com",
                },
            }
        )

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/create-username-account",
                "requestContext": {"http": {"method": "POST"}},
                "body": (
                    '{"username":"student_1","display_name":"Student One",'
                    '"password":"Password123!","email":"student@example.com"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"created": true', result["body"])
        call = admin_module.repo.create_calls[0]
        self.assertEqual(call["username"], "student_1")
        self.assertEqual(call["display_name"], "Student One")
        self.assertEqual(call["password"], "Password123!")
        self.assertEqual(call["email"], "student@example.com")
        self.assertEqual(call["created_by_email"], "admin@example.com")

    def test_create_username_account_returns_bad_request_for_invalid_input(self):
        self._authenticate()
        repo = _FakeRepo()
        repo.create_error = ValueError("That username is already taken.")
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/create-username-account",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"username":"student_1","display_name":"Student One","password":"Password123!"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("That username is already taken", result["body"])

    def test_delete_returns_bad_request_for_missing_reason(self):
        self._authenticate()
        repo = _FakeRepo()
        repo.delete_error = ValueError("Deletion reason is required.")
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/delete",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"user_id":"user-1","confirm_email":"user@example.com"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("Deletion reason is required", result["body"])

    def test_delete_requires_force_when_repo_says_so(self):
        self._authenticate()
        repo = _FakeRepo()
        repo.delete_error = admin_module.AdminDeleteRequiresForceError(
            "force required",
            snapshot={"user_id": "user-1", "has_active_subscription": True},
        )
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/delete",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"user_id":"user-1","reason":"duplicate","confirm_email":"user@example.com"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 409)
        self.assertIn('"requires_force": true', result["body"])
        self.assertIn('"user_id": "user-1"', result["body"])

    def test_delete_returns_payload(self):
        self._authenticate()
        admin_module.repo = _FakeRepo(
            delete_payload={
                "deleted": True,
                "user_id": "user-1",
                "deleted_resources": {"cognito_user": True},
            }
        )

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/delete",
                "requestContext": {"http": {"method": "POST"}},
                "body": "{\"user_id\":\"user-1\",\"reason\":\"test cleanup\",\"confirm_email\":\"user@example.com\",\"force\":true}",
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"deleted": true', result["body"])
        self.assertIn('"cognito_user": true', result["body"])
        self.assertTrue(admin_module.repo.delete_calls[0]["force"])
        self.assertEqual(admin_module.repo.delete_calls[0]["confirm_email"], "user@example.com")

    def test_grant_prompt_allowance_returns_payload(self):
        self._authenticate(email="andrew@mixroom.ai")
        admin_module.repo = _FakeRepo(
            grant_payload={
                "granted": True,
                "user_id": "user-1",
                "granted_prompts": 25,
            }
        )

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/grant-prompts",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"user_id":"user-1","prompt_count":25}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"granted": true', result["body"])
        self.assertIn('"granted_prompts": 25', result["body"])
        self.assertEqual(admin_module.repo.grant_calls[0]["prompt_count"], 25)

    def test_grant_prompt_allowance_requires_ai_editor_email(self):
        self._authenticate(email="other-admin@example.com")
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/grant-prompts",
                "requestContext": {"http": {"method": "POST"}},
                "body": '{"user_id":"user-1","prompt_count":25}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("andrew@mixroom.ai", result["body"])

    def test_entitlement_override_returns_payload(self):
        self._authenticate(email="andrew@mixroom.ai")
        admin_module.repo = _FakeRepo(
            override_payload={
                "overridden": True,
                "override_id": "override-1",
                "user": {"user_id": "user-1", "subscription_tier": "producer"},
            }
        )

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/entitlement-override",
                "requestContext": {"http": {"method": "POST"}},
                "body": (
                    '{"user_id":"user-1","plan_code":"studio",'
                    '"expires_at":"2026-05-20T00:00:00+00:00",'
                    '"seat_limit":5,"organization_name":"Test Studio",'
                    '"reason":"support test","confirm_identifier":"user@example.com",'
                    '"confirm_admin_first_name":"andrew"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"overridden": true', result["body"])
        call = admin_module.repo.override_calls[0]
        self.assertEqual(call["plan_code"], "studio")
        self.assertEqual(call["seat_limit"], 5)
        self.assertEqual(call["organization_name"], "Test Studio")

    def test_entitlement_override_allows_allowlisted_employee_admin(self):
        self._authenticate(email="other-admin@example.com")
        admin_module.repo = _FakeRepo(override_payload={"overridden": True})

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/users/entitlement-override",
                "requestContext": {"http": {"method": "POST"}},
                "body": (
                    '{"user_id":"user-1","plan_code":"producer",'
                    '"expires_at":"2026-05-20T00:00:00+00:00",'
                    '"reason":"manual sale","confirm_identifier":"user@example.com",'
                    '"confirm_admin_first_name":"other-admin"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"overridden": true', result["body"])
        call = admin_module.repo.override_calls[0]
        self.assertEqual(call["granted_by_email"], "other-admin@example.com")
        self.assertEqual(call["plan_code"], "producer")


class AdminUserRepositoryTests(unittest.TestCase):
    def test_create_username_account_writes_native_account_profile_and_free_entitlement(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        billing_repo = mock.Mock()
        billing_repo.get_auth_account_by_email.return_value = None
        billing_repo.get_user_profile_by_username.return_value = None
        billing_repo.get_entitlement.return_value = None
        repository._billing_repo = billing_repo
        repository._get_entitlement = mock.Mock(return_value={"user_id": "user-1", "plan_code": "free"})
        repository._build_user_record = mock.Mock(
            return_value={
                "user_id": "user-1",
                "username": "student_1",
                "email": "student@example.com",
                "email_verified": True,
            }
        )

        payload = repository.create_username_account(
            username="Student_1",
            display_name="Student One",
            password="Password123!",
            email="Student@Example.com",
            created_by_user_id="admin-user",
            created_by_email="Admin@Example.com",
        )

        self.assertTrue(payload["created"])
        account = billing_repo.put_auth_account.call_args.args[0]
        profile = billing_repo.upsert_user_profile.call_args.args[0]
        self.assertEqual(account["username"] if "username" in account else profile["username"], "student_1")
        self.assertEqual(account["email"], "student@example.com")
        self.assertTrue(account["email_verified"])
        self.assertEqual(account["auth_provider"], "email")
        self.assertTrue(account["password_hash"])
        self.assertEqual(profile["username_lc"], "student_1")
        self.assertEqual(profile["onboarding_state"], "signup_complete")
        self.assertEqual(profile["accepted_terms_version"], "admin_provisioned")
        billing_repo.put_entitlement.assert_called_once()

    def test_create_username_account_allows_blank_email(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        billing_repo = mock.Mock()
        billing_repo.get_user_profile_by_username.return_value = None
        billing_repo.get_entitlement.return_value = None
        repository._billing_repo = billing_repo
        repository._get_entitlement = mock.Mock(return_value={"user_id": "user-1", "plan_code": "free"})
        repository._build_user_record = mock.Mock(return_value={"user_id": "user-1"})

        repository.create_username_account(
            username="student_1",
            display_name="Student One",
            password="Password123!",
            email="",
            created_by_user_id="admin-user",
            created_by_email="admin@example.com",
        )

        account = billing_repo.put_auth_account.call_args.args[0]
        self.assertEqual(account["email"], "")
        self.assertNotIn("email_lc", account)
        self.assertTrue(account["email_verified"])

    def test_override_seat_limits_follow_team_plan_rules(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)

        self.assertEqual(
            repository._normalize_override_seat_limit(
                "studio",
                None,
                plan={"limits": {"members": 5}},
            ),
            5,
        )
        self.assertEqual(
            repository._normalize_override_seat_limit(
                "education",
                73,
                plan={"limits": {"default_seats": 20}},
            ),
            73,
        )

        with self.assertRaisesRegex(ValueError, "Studio seat limit"):
            repository._normalize_override_seat_limit(
                "studio",
                4,
                plan={"limits": {"members": 5}},
            )
        with self.assertRaisesRegex(ValueError, "Education seat limit"):
            repository._normalize_override_seat_limit(
                "education",
                -1,
                plan={"limits": {"default_seats": 20}},
            )

    def test_build_user_record_prefers_native_auth_fields_and_summarizes_sessions(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._list_auth_sessions_for_user = mock.Mock(
            return_value=[
                {
                    "session_id": "session-1",
                    "created_at": "2026-03-20T10:00:00+00:00",
                    "expires_at": "2999-01-01T00:00:00+00:00",
                },
                {
                    "session_id": "session-2",
                    "created_at": "2026-03-19T10:00:00+00:00",
                    "expires_at": "2026-03-19T11:00:00+00:00",
                },
            ]
        )
        repository._get_ai_usage_state = mock.Mock(return_value={})
        repository._get_entitlement = mock.Mock(
            return_value={"plan_code": "producer", "status": "active", "source_provider": "apple"}
        )
        repository._list_subscriptions_for_user = mock.Mock(return_value=[])
        repository._list_customer_link_items = mock.Mock(
            return_value=[{"provider": "google"}]
        )
        repository._latest_linked_at = mock.Mock(return_value="2026-03-20T09:00:00+00:00")

        record = repository._build_user_record(
            "user-1",
            app_profile={
                "user_id": "user-1",
                "email": "profile@example.com",
                "display_name": "Profile Name",
                "music_profile": "music_enthusiast",
                "auth_provider": "email",
                "email_verified": False,
                "profile_status": "active",
                "onboarding_state": "ready",
                "cognito_username": "legacy-name",
                "created_at": "2026-03-01T00:00:00+00:00",
                "updated_at": "2026-03-10T00:00:00+00:00",
            },
            auth_account={
                "user_id": "user-1",
                "email": "native@example.com",
                "auth_provider": "google",
                "email_verified": True,
                "legacy_cognito_enabled": True,
                "legacy_cognito_username": "legacy-cognito-user",
                "legacy_cognito_migrated_at": "2026-03-20T10:43:15+00:00",
            },
            cognito_profile={
                "username": "cognito-fallback",
                "auth_status": "CONFIRMED",
                "account_enabled": False,
            },
            warnings=[],
            ai_usage_state={},
            entitlement={"plan_code": "producer", "status": "active", "source_provider": "apple"},
            subscriptions=[],
            customer_links=[{"provider": "google"}],
        )

        self.assertEqual(record["email"], "native@example.com")
        self.assertEqual(record["auth_provider"], "google")
        self.assertEqual(record["auth_source"], "native_legacy_bridge")
        self.assertEqual(record["auth_status"], "native_legacy_bridge")
        self.assertEqual(record["music_profile"], "music_enthusiast")
        self.assertTrue(record["email_verified"])
        self.assertTrue(record["native_auth_exists"])
        self.assertEqual(record["native_session_count"], 2)
        self.assertEqual(record["native_active_session_count"], 1)
        self.assertEqual(record["legacy_cognito_username"], "legacy-cognito-user")
        self.assertEqual(record["legacy_auth_status"], "CONFIRMED")
        self.assertIn("google", record["linked_providers"])

    def test_load_user_record_skips_cognito_lookup_when_native_account_exists(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._get_user_profile = mock.Mock(
            return_value={"user_id": "user-1", "email": "user@example.com"}
        )
        repository._get_auth_account = mock.Mock(
            return_value={"user_id": "user-1", "email": "user@example.com"}
        )
        repository._get_ai_usage_state = mock.Mock(return_value={})
        repository._get_cognito_profile_for_user_id = mock.Mock(
            side_effect=AssertionError("Cognito lookup should not run")
        )
        repository._build_user_record = mock.Mock(return_value={"user_id": "user-1"})

        record = repository._load_user_record("user-1", [])

        self.assertEqual(record["user_id"], "user-1")
        repository._build_user_record.assert_called_once()
        called = repository._build_user_record.call_args.kwargs
        self.assertEqual(called["auth_account"]["user_id"], "user-1")
        self.assertEqual(called["cognito_profile"], {})

    def test_load_user_record_skips_cognito_lookup_when_app_profile_exists_without_native_auth(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._get_user_profile = mock.Mock(
            return_value={"user_id": "user-1", "email": "user@example.com"}
        )
        repository._get_auth_account = mock.Mock(return_value={})
        repository._get_ai_usage_state = mock.Mock(return_value={})
        repository._get_cognito_profile_for_user_id = mock.Mock(
            side_effect=AssertionError("Cognito lookup should not run")
        )
        repository._build_user_record = mock.Mock(return_value={"user_id": "user-1"})

        record = repository._load_user_record("user-1", [])

        self.assertEqual(record["user_id"], "user-1")
        repository._build_user_record.assert_called_once()
        called = repository._build_user_record.call_args.kwargs
        self.assertEqual(called["app_profile"]["user_id"], "user-1")
        self.assertEqual(called["cognito_profile"], {})

    def test_search_candidate_user_ids_uses_native_email_lookup_without_cognito(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._get_user_profile = mock.Mock(return_value={})
        repository._get_user_profile_by_username = mock.Mock(return_value={})
        repository._get_user_profile_by_email = mock.Mock(return_value={})
        repository._get_auth_account_by_email = mock.Mock(
            return_value={"user_id": "native-user"}
        )
        repository._fallback_recent_user_ids = mock.Mock(return_value=[])
        repository._get_cognito_profile_by_email = mock.Mock(
            side_effect=AssertionError("Cognito email lookup should not run")
        )

        user_ids = repository._search_candidate_user_ids(
            "native@example.com",
            limit=24,
            warnings=[],
        )

        self.assertEqual(user_ids, ["native-user"])

    def test_subscription_candidate_user_ids_separates_paying_and_granted(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._entitlements = mock.Mock()
        repository._entitlements.scan.return_value = {
            "Items": [
                {
                    "user_id": "paying-user",
                    "plan_code": "producer",
                    "status": "active",
                    "source_provider": "apple",
                },
                {
                    "user_id": "trial-user",
                    "plan_code": "producer",
                    "status": "trialing",
                    "source_provider": "paddle",
                },
                {
                    "user_id": "granted-user",
                    "plan_code": "studio",
                    "status": "active",
                    "source_provider": "admin_grant",
                },
                {
                    "user_id": "free-user",
                    "plan_code": "free",
                    "status": "active",
                    "source_provider": "admin_grant",
                },
            ]
        }

        paying = repository._list_subscription_candidate_user_ids(
            "paying",
            warnings=[],
        )
        granted = repository._list_subscription_candidate_user_ids(
            "granted",
            warnings=[],
        )

        self.assertEqual(paying, ["paying-user"])
        self.assertEqual(granted, ["granted-user"])

    def test_fallback_recent_user_ids_no_longer_reads_recent_cognito_users(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._list_recent_app_profiles = mock.Mock(return_value=[])
        repository._list_recent_cognito_user_ids = mock.Mock(
            side_effect=AssertionError("Recent Cognito listing should not run")
        )

        result = repository._fallback_recent_user_ids(limit=24, warnings=[])

        self.assertEqual(result, [])

    def test_delete_cognito_user_ignores_missing_cognito_record(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._cognito = mock.Mock()
        repository._cognito.admin_delete_user.side_effect = exceptions_stub.ClientError(
            {"Error": {"Code": "UserNotFoundException"}},
            "AdminDeleteUser",
        )

        repo_module.config.COGNITO_USER_POOL_ID = "pool-id"

        repository._delete_cognito_user("missing-user")

    def test_delete_cognito_user_still_raises_other_cognito_errors(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._cognito = mock.Mock()
        repository._cognito.admin_delete_user.side_effect = exceptions_stub.ClientError(
            {"Error": {"Code": "TooManyRequestsException"}},
            "AdminDeleteUser",
        )

        repo_module.config.COGNITO_USER_POOL_ID = "pool-id"

        with self.assertRaises(exceptions_stub.ClientError):
            repository._delete_cognito_user("rate-limited-user")

    def test_delete_user_skips_cognito_delete_for_native_only_profile(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._tombstones = mock.Mock()
        repository._billing_repo = mock.Mock()
        repository._get_user_profile = mock.Mock(
            return_value={"user_id": "user-1", "cognito_username": "stale-profile-value"}
        )
        repository._get_auth_account = mock.Mock(
            return_value={
                "user_id": "user-1",
                "email": "user@example.com",
                "auth_provider": "email",
                "legacy_cognito_enabled": False,
            }
        )
        repository._get_entitlement = mock.Mock(return_value={})
        repository._list_subscriptions_for_user = mock.Mock(return_value=[])
        repository._list_customer_link_items = mock.Mock(return_value=[])
        repository._list_purchase_tokens = mock.Mock(return_value=[])
        repository._build_user_record = mock.Mock(return_value={"has_active_subscription": False})
        repository._mark_tombstone = mock.Mock()
        repository._delete_cognito_user = mock.Mock()

        repository.delete_user(
            user_id="user-1",
            deleted_by_user_id="admin-1",
            deleted_by_email="admin@example.com",
            reason="cleanup",
            confirm_email="user@example.com",
            force=False,
        )

        repository._delete_cognito_user.assert_not_called()

    def test_delete_user_requires_matching_confirm_email(self):
        repository = repo_module.AdminUserRepository.__new__(repo_module.AdminUserRepository)
        repository._tombstones = mock.Mock()
        repository._billing_repo = mock.Mock()
        repository._get_user_profile = mock.Mock(return_value={})
        repository._get_auth_account = mock.Mock(
            return_value={
                "user_id": "user-1",
                "email": "user@example.com",
                "auth_provider": "email",
            }
        )
        repository._get_entitlement = mock.Mock(return_value={})
        repository._list_subscriptions_for_user = mock.Mock(return_value=[])
        repository._list_customer_link_items = mock.Mock(return_value=[])
        repository._list_purchase_tokens = mock.Mock(return_value=[])
        repository._build_user_record = mock.Mock(
            return_value={
                "user_id": "user-1",
                "email": "user@example.com",
                "has_active_subscription": False,
            }
        )
        repository._mark_tombstone = mock.Mock()
        repository._delete_cognito_user = mock.Mock()

        with self.assertRaisesRegex(ValueError, "login email exactly"):
            repository.delete_user(
                user_id="user-1",
                deleted_by_user_id="admin-1",
                deleted_by_email="admin@example.com",
                reason="cleanup",
                confirm_email="other@example.com",
                force=False,
            )


if __name__ == "__main__":
    unittest.main()
