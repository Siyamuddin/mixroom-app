import importlib
import json
import os
import sys
import unittest
from decimal import Decimal
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

if "jwt" not in sys.modules:
    jwt_stub = ModuleType("jwt")
    jwt_stub.get_unverified_header = mock.Mock(return_value={})
    jwt_stub.decode = mock.Mock(return_value={})
    jwt_stub.algorithms = SimpleNamespace(
        RSAAlgorithm=SimpleNamespace(from_jwk=mock.Mock(return_value=object()))
    )
    sys.modules["jwt"] = jwt_stub

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

users_module = importlib.import_module("src.handlers.api_users")


class _FakeRepo:
    def __init__(self, existing_claim=None):
        self._existing_claim = existing_claim
        self._profile = {}
        self._entitlement = {}
        self._auth_account = {}
        self.delete_calls = []
        self.upsert_calls = []

    def get_username_claim(self, username_lc):
        if self._existing_claim and username_lc == self._existing_claim["username_lc"]:
            return dict(self._existing_claim)
        return None

    def get_user_profile(self, user_id):
        return dict(self._profile)

    def get_entitlement(self, user_id):
        return dict(self._entitlement)

    def get_auth_account(self, user_id):
        return dict(self._auth_account)

    def upsert_user_profile(self, profile, *, previous_username_lc=None):
        self.upsert_calls.append(
            {
                "profile": dict(profile),
                "previous_username_lc": previous_username_lc,
            }
        )
        self._profile = dict(profile)

    def delete_user_account_data(self, user_id, *, username_lc=None):
        self.delete_calls.append({"user_id": user_id, "username_lc": username_lc})


class _FakeProducerCaptureWhitelistRepo:
    def __init__(self, settings=None):
        self._settings = settings or {
            "usernames": [],
            "source": "default",
            "configurable": True,
        }

    def get_whitelist_settings(self):
        return dict(self._settings)


class UsersApiHandlerTests(unittest.TestCase):
    def setUp(self):
        self._original_repo = users_module.repo
        self._original_whitelist_repo = users_module.producer_capture_whitelist_repo
        self._original_extract_claims = users_module.extract_claims_from_event
        self._original_rate_limiter = users_module.rate_limiter
        self._original_users_table = users_module.config.USERS_TABLE
        self._original_username_claims_table = users_module.config.USERNAME_CLAIMS_TABLE
        users_module.config.USERS_TABLE = "users"
        users_module.config.USERNAME_CLAIMS_TABLE = "username-claims"

    def tearDown(self):
        users_module.repo = self._original_repo
        users_module.producer_capture_whitelist_repo = self._original_whitelist_repo
        users_module.extract_claims_from_event = self._original_extract_claims
        users_module.rate_limiter = self._original_rate_limiter
        users_module.config.USERS_TABLE = self._original_users_table
        users_module.config.USERNAME_CLAIMS_TABLE = self._original_username_claims_table

    def test_reports_available_username(self):
        users_module.repo = _FakeRepo()

        result = users_module.handler(
            {
                "rawPath": "/v1/users/username-availability",
                "requestContext": {"http": {"method": "GET"}},
                "queryStringParameters": {"username": "mixroomer"},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"available": true', result["body"])

    def test_reports_taken_username(self):
        users_module.repo = _FakeRepo(
            existing_claim={
                "username_lc": "mixroomer",
                "user_id": "user-123",
            }
        )

        result = users_module.handler(
            {
                "rawPath": "/v1/users/username-availability",
                "requestContext": {"http": {"method": "GET"}},
                "queryStringParameters": {"username": "mixroomer"},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"available": false', result["body"])
        self.assertIn('already taken', result["body"])

    def test_reports_producer_capture_access_enabled_for_allowlisted_username(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-123",
            "username": "andrewtest",
            "username_lc": "andrewtest",
        }
        users_module.repo = repo
        users_module.producer_capture_whitelist_repo = _FakeProducerCaptureWhitelistRepo(
            settings={
                "usernames": ["andrewtest", "lavitababy1004"],
                "source": "remote",
                "configurable": True,
            }
        )
        users_module.extract_claims_from_event = lambda event: {"sub": "user-123"}

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me/producer-capture-ui-access",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"enabled": true', result["body"])
        self.assertIn('"username": "andrewtest"', result["body"])
        self.assertIn('"source": "remote"', result["body"])

    def test_reports_producer_capture_access_disabled_for_non_allowlisted_username(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-123",
            "username": "someoneelse",
            "username_lc": "someoneelse",
        }
        users_module.repo = repo
        users_module.producer_capture_whitelist_repo = _FakeProducerCaptureWhitelistRepo(
            settings={
                "usernames": ["andrewtest", "lavitababy1004"],
                "source": "remote",
                "configurable": True,
            }
        )
        users_module.extract_claims_from_event = lambda event: {"sub": "user-123"}

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me/producer-capture-ui-access",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"enabled": false', result["body"])
        self.assertIn('"username": "someoneelse"', result["body"])

    def test_username_availability_returns_429_when_rate_limited(self):
        class _Decision:
            def __init__(self, allowed, retry_after_seconds, reason):
                self.allowed = allowed
                self.retry_after_seconds = retry_after_seconds
                self.reason = reason

        users_module.repo = _FakeRepo()
        users_module.rate_limiter = mock.Mock()
        users_module.rate_limiter.enforce.return_value = _Decision(False, 11, "blocked")

        result = users_module.handler(
            {
                "rawPath": "/v1/users/username-availability",
                "requestContext": {"http": {"method": "GET", "sourceIp": "1.2.3.4"}},
                "queryStringParameters": {"username": "mixroomer"},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 429)
        self.assertEqual(result["headers"]["Retry-After"], "11")
        self.assertIn('"code": "RATE_LIMITED"', result["body"])

    def test_delete_me_blocks_active_paid_subscription(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        repo._entitlement = {
            "tier": "pro",
            "status": "active",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        with mock.patch.object(users_module, "verify_current_password") as verify_password:
            result = users_module.handler(
                {
                    "rawPath": "/v1/users/me",
                    "requestContext": {"http": {"method": "DELETE"}},
                    "body": '{"confirmation_text":"DELETE","current_password":"secret"}',
                },
                object(),
            )

        self.assertEqual(result["statusCode"], 409)
        self.assertIn("Cancel your active subscription first", result["body"])
        self.assertEqual(repo.delete_calls, [])
        verify_password.assert_not_called()

    def test_delete_me_requires_delete_confirmation_text(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "DELETE"}},
                "body": '{"confirmation_text":"remove","current_password":"secret"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("DELETE_CONFIRMATION_REQUIRED", result["body"])
        self.assertEqual(repo.delete_calls, [])

    def test_delete_me_requires_password_for_email_accounts(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "DELETE"}},
                "body": '{"confirmation_text":"DELETE"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("DELETE_PASSWORD_REQUIRED", result["body"])
        self.assertEqual(repo.delete_calls, [])

    def test_delete_me_rejects_invalid_current_password(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        with mock.patch.object(
            users_module,
            "verify_current_password",
            side_effect=users_module.AppUserAuthError(
                "Current password is incorrect.",
                code="INVALID_CURRENT_PASSWORD",
                status_code=400,
            ),
        ):
            result = users_module.handler(
                {
                    "rawPath": "/v1/users/me",
                    "requestContext": {"http": {"method": "DELETE"}},
                    "body": '{"confirmation_text":"DELETE","current_password":"bad"}',
                },
                object(),
            )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("INVALID_CURRENT_PASSWORD", result["body"])
        self.assertEqual(repo.delete_calls, [])

    def test_delete_me_deletes_email_account_after_confirmation_and_password_check(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        repo._profile = {
            "user_id": "user-1",
            "username_lc": "mixroomer",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        with mock.patch.object(users_module, "verify_current_password") as verify_password:
            result = users_module.handler(
                {
                    "rawPath": "/v1/users/me",
                    "requestContext": {"http": {"method": "DELETE"}},
                    "body": '{"confirmation_text":"DELETE","current_password":"secret"}',
                },
                object(),
            )

        self.assertEqual(result["statusCode"], 200)
        verify_password.assert_called_once_with(
            repo,
            user_id="user-1",
            current_password="secret",
        )
        self.assertEqual(
            repo.delete_calls,
            [{"user_id": "user-1", "username_lc": "mixroomer"}],
        )

    def test_delete_me_requires_social_reauth_for_social_accounts(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "google",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "DELETE"}},
                "body": '{"confirmation_text":"DELETE"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("SOCIAL_REAUTH_REQUIRED", result["body"])
        self.assertEqual(repo.delete_calls, [])

    def test_delete_me_deletes_social_account_after_reauth(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "google",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        with mock.patch.object(
            users_module,
            "verify_social_reauthentication",
        ) as verify_social:
            result = users_module.handler(
                {
                    "rawPath": "/v1/users/me",
                    "requestContext": {"http": {"method": "DELETE"}},
                    "body": (
                        '{"confirmation_text":"DELETE","social_reauth":'
                        '{"id_token":"token"}}'
                    ),
                },
                object(),
            )

        self.assertEqual(result["statusCode"], 200)
        verify_social.assert_called_once_with(
            repo,
            user_id="user-1",
            payload={"id_token": "token"},
        )
        self.assertEqual(len(repo.delete_calls), 1)

    def test_get_me_does_not_write_when_profile_is_already_current(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "profile_status": "active",
            "schema_version": 4,
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(repo.upsert_calls, [])

    def test_get_me_serializes_decimal_fields_from_dynamodb_profile(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "profile_status": "active",
            "schema_version": Decimal("4"),
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"schema_version": 4', result["body"])
        self.assertEqual(repo.upsert_calls, [])

    def test_get_me_bootstraps_when_profile_is_missing_required_fields(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(len(repo.upsert_calls), 1)
        self.assertEqual(
            repo.upsert_calls[0]["profile"]["email_lc"],
            "user@example.com",
        )

    def test_patch_me_accepts_music_profile(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User Example",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": "mixroomer",
            "username_lc": "mixroomer",
            "music_profile": None,
            "profile_status": "active",
            "onboarding_state": "bootstrap_only",
            "accepted_terms_version": None,
            "accepted_privacy_version": None,
            "accepted_at": None,
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-01-01T00:00:00+00:00",
            "last_seen_at": "2026-01-01T00:00:00+00:00",
            "schema_version": 4,
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "PATCH"}},
                "body": '{"music_profile":"producer"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(repo.upsert_calls[-1]["profile"]["music_profile"], "producer")
        self.assertIn('"music_profile": "producer"', result["body"])

    def test_patch_me_does_not_generate_username_when_signup_completion_has_no_username(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": None,
            "username_lc": None,
            "music_profile": None,
            "profile_status": "active",
            "onboarding_state": "bootstrap_only",
            "accepted_terms_version": None,
            "accepted_privacy_version": None,
            "accepted_at": None,
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-01-01T00:00:00+00:00",
            "last_seen_at": "2026-01-01T00:00:00+00:00",
            "schema_version": 4,
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "PATCH"}},
                "body": (
                    '{"birthdate":"1998-08-09",'
                    '"accepted_terms_version":"2026-03-10",'
                    '"accepted_privacy_version":"2026-03-10"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload.get("username"), None)
        self.assertEqual(payload.get("onboarding_state"), "profile_ready")

    def test_patch_me_does_not_generate_username_without_birthdate(self):
        repo = _FakeRepo()
        repo._profile = {
            "user_id": "user-1",
            "email": "user@example.com",
            "email_lc": "user@example.com",
            "display_name": "User",
            "email_verified": True,
            "cognito_username": "user@example.com",
            "auth_provider": "email",
            "username": None,
            "username_lc": None,
            "music_profile": None,
            "profile_status": "active",
            "onboarding_state": "bootstrap_only",
            "accepted_terms_version": None,
            "accepted_privacy_version": None,
            "accepted_at": None,
            "newsletter_opt_in": False,
            "newsletter_opt_in_at": None,
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-01-01T00:00:00+00:00",
            "last_seen_at": "2026-01-01T00:00:00+00:00",
            "schema_version": 4,
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {
            "sub": "user-1",
            "email": "user@example.com",
            "email_verified": "true",
            "cognito:username": "user@example.com",
        }

        result = users_module.handler(
            {
                "rawPath": "/v1/users/me",
                "requestContext": {"http": {"method": "PATCH"}},
                "body": (
                    '{"birthdate":null,'
                    '"accepted_terms_version":"2026-03-10",'
                    '"accepted_privacy_version":"2026-03-10"}'
                ),
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload.get("birthdate"), None)
        self.assertEqual(payload.get("username"), None)
        self.assertEqual(payload.get("onboarding_state"), "bootstrap_only")

    def test_delete_me_removes_account_for_free_user(self):
        repo = _FakeRepo()
        repo._auth_account = {
            "user_id": "user-1",
            "auth_provider": "email",
        }
        repo._profile = {"username_lc": "mixroomer"}
        repo._entitlement = {
            "tier": "free",
            "status": "active",
        }
        users_module.repo = repo
        users_module.extract_claims_from_event = lambda event: {"sub": "user-1"}

        with mock.patch.object(users_module, "verify_current_password") as verify_password:
            result = users_module.handler(
                {
                    "rawPath": "/v1/users/me",
                    "requestContext": {"http": {"method": "DELETE"}},
                    "body": '{"confirmation_text":"DELETE","current_password":"secret"}',
                },
                object(),
            )

        self.assertEqual(result["statusCode"], 200)
        verify_password.assert_called_once_with(
            repo,
            user_id="user-1",
            current_password="secret",
        )
        self.assertEqual(
            repo.delete_calls,
            [{"user_id": "user-1", "username_lc": "mixroomer"}],
        )


if __name__ == "__main__":
    unittest.main()
