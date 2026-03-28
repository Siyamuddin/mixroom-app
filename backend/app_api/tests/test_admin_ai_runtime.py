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

admin_module = importlib.import_module("src.handlers.api_admin_ai_runtime")
runtime_repo_module = importlib.import_module("src.common.admin_ai_runtime_repository")
runtime_defaults_module = importlib.import_module("src.common.ai_runtime_defaults")


class _FakeRepo:
    def __init__(self) -> None:
        self.get_payload = {
            "features": [
                {
                    "feature": "ai_chat",
                    "model_override": "",
                    "system_prompt_override": "",
                    "source": "default",
                    "default_runtime": {
                        "model": "gpt-4.1-mini",
                        "max_output_tokens": None,
                        "temperature": 0.2,
                        "reasoning_effort": "",
                        "prompt_cache_retention": "in_memory",
                    },
                }
            ]
        }
        self.update_payload = {
            "feature": "ai_chat",
            "model_override": "gpt-5-mini",
            "system_prompt_override": "Use the override.",
            "source": "remote",
        }
        self.update_calls = []

    def get_runtime_settings(self):
        return dict(self.get_payload)

    def update_feature_runtime(self, **kwargs):
        self.update_calls.append(dict(kwargs))
        return dict(self.update_payload)


class _FakeAccessRepo:
    def __init__(self, allowed_emails):
        self.allowed_emails = {email.strip().lower() for email in allowed_emails}

    def is_email_allowed(self, email):
        return email.strip().lower() in self.allowed_emails


class AdminAiRuntimeHandlerTests(unittest.TestCase):
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

    def test_get_returns_runtime_settings(self):
        self._authenticate()
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-runtime",
                "requestContext": {"http": {"method": "GET"}},
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertIn('"can_edit": false', result["body"])
        self.assertIn('"feature": "ai_chat"', result["body"])

    def test_put_requires_ai_editor_email(self):
        self._authenticate(email="other-admin@example.com")
        admin_module.repo = _FakeRepo()

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-runtime",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"feature":"ai_chat","model_override":"gpt-5-mini"}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 403)
        self.assertIn("andrew@mixroom.ai", result["body"])

    def test_put_updates_runtime_for_ai_editor(self):
        self._authenticate(email="andrew@mixroom.ai")
        repo = _FakeRepo()
        admin_module.repo = repo

        result = admin_module.handler(
            {
                "rawPath": "/v1/internal/admin/settings/ai-runtime",
                "requestContext": {"http": {"method": "PUT"}},
                "body": '{"feature":"ai_chat","model_override":"gpt-5-mini","system_prompt_override":"Use the override."}',
            },
            object(),
        )

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(repo.update_calls[0]["feature"], "ai_chat")
        self.assertEqual(repo.update_calls[0]["updated_by_email"], "andrew@mixroom.ai")


class AdminAiRuntimeRepositoryTests(unittest.TestCase):
    def test_rejects_invalid_model_override(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )
        repository._table = object()

        with self.assertRaisesRegex(ValueError, "approved server models"):
            repository.update_feature_runtime(
                feature="ai_chat",
                model_override="totally-invalid-model",
                system_prompt_override="",
                max_output_tokens_override="",
                temperature_override="",
                reasoning_effort_override="",
                prompt_cache_retention_override="",
                updated_by_user_id="admin-user",
                updated_by_email="andrew@mixroom.ai",
            )

    def test_rejects_invalid_reasoning_effort_override(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )
        repository._table = object()

        with self.assertRaisesRegex(ValueError, "minimal, low, medium, high"):
            repository.update_feature_runtime(
                feature="ai_chat",
                model_override="",
                system_prompt_override="",
                max_output_tokens_override="",
                temperature_override="",
                reasoning_effort_override="extreme",
                prompt_cache_retention_override="",
                updated_by_user_id="admin-user",
                updated_by_email="andrew@mixroom.ai",
            )

    def test_rejects_invalid_prompt_cache_retention_override(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )
        repository._table = object()

        with self.assertRaisesRegex(ValueError, "in_memory, 24h"):
            repository.update_feature_runtime(
                feature="ai_chat",
                model_override="",
                system_prompt_override="",
                max_output_tokens_override="",
                temperature_override="",
                reasoning_effort_override="",
                prompt_cache_retention_override="7d",
                updated_by_user_id="admin-user",
                updated_by_email="andrew@mixroom.ai",
            )

    def test_serializes_default_runtime_for_ai_chat(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )

        serialized = repository._serialize_feature("ai_chat", {})

        self.assertEqual(serialized["default_runtime"]["model"], "gpt-4.1-mini")
        self.assertEqual(serialized["default_runtime"]["temperature"], 0.2)
        self.assertEqual(serialized["default_runtime"]["prompt_cache_retention"], "in_memory")

    def test_serializes_default_runtime_for_video_editor_chat(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )

        serialized = repository._serialize_feature("video_editor_chat", {})

        self.assertEqual(serialized["default_runtime"]["model"], "gpt-4.1-mini")
        self.assertEqual(serialized["default_runtime"]["temperature"], 0.1)
        self.assertEqual(serialized["default_runtime"]["prompt_cache_retention"], "")

    def test_serialized_default_runtime_uses_config_backed_values(self):
        repository = runtime_repo_module.AdminAiRuntimeRepository.__new__(
            runtime_repo_module.AdminAiRuntimeRepository
        )

        with mock.patch.object(
            runtime_defaults_module.config,
            "AI_RUNTIME_DEFAULT_MODEL",
            "gpt-5.2",
        ), mock.patch.object(
            runtime_defaults_module.config,
            "AI_CHAT_DEFAULT_TEMPERATURE",
            0.35,
        ), mock.patch.object(
            runtime_defaults_module.config,
            "AI_CHAT_EXTENDED_PROMPT_CACHE_RETENTION_MODELS",
            frozenset({"gpt-5.2"}),
        ):
            serialized = repository._serialize_feature("ai_chat", {})

        self.assertEqual(serialized["default_runtime"]["model"], "gpt-5.2")
        self.assertEqual(serialized["default_runtime"]["temperature"], 0.35)
        self.assertEqual(serialized["default_runtime"]["reasoning_effort"], "minimal")
        self.assertEqual(serialized["default_runtime"]["prompt_cache_retention"], "24h")


if __name__ == "__main__":
    unittest.main()
