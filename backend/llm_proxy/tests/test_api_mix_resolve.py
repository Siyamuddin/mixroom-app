from __future__ import annotations

import base64
import json
import os
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

for key, value in {
    "APP_AUTH_SECRET_ARN": "app-auth-secret",
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
}.items():
    os.environ.setdefault(key, value)

if "boto3" not in sys.modules:
    boto3_stub = ModuleType("boto3")
    boto3_stub.client = mock.Mock(return_value=mock.Mock())
    boto3_stub.resource = mock.Mock(
        return_value=SimpleNamespace(Table=mock.Mock(return_value=mock.Mock()))
    )
    sys.modules["boto3"] = boto3_stub

from common import auth as auth_module  # noqa: E402
from handlers import api_mix_resolve  # noqa: E402


class _FakeTable:
    def __init__(self, items=None) -> None:
        self.items = dict(items or {})

    def get_item(self, *, Key):
        _, key_value = next(iter(Key.items()))
        return {"Item": self.items.get(key_value)} if key_value in self.items else {}

    def delete_item(self, *, Key):
        _, key_value = next(iter(Key.items()))
        self.items.pop(key_value, None)


class MixResolveHandlerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_sessions = auth_module._auth_sessions
        self.original_accounts = auth_module._auth_accounts
        self.original_secret_arn = auth_module.config.APP_AUTH_SECRET_ARN
        self.original_resolver = api_mix_resolve._resolver
        auth_module.config.APP_AUTH_SECRET_ARN = "app-auth-secret"
        auth_module._auth_sessions = _FakeTable(
            {
                "session-1": {
                    "session_id": "session-1",
                    "user_id": "user-1",
                }
            }
        )
        auth_module._auth_accounts = _FakeTable({"user-1": {"user_id": "user-1"}})

    def tearDown(self) -> None:
        auth_module._auth_sessions = self.original_sessions
        auth_module._auth_accounts = self.original_accounts
        auth_module.config.APP_AUTH_SECRET_ARN = self.original_secret_arn
        api_mix_resolve._resolver = self.original_resolver

    def test_requires_auth(self) -> None:
        result = api_mix_resolve.handler({"headers": {}, "body": "{}"}, None)
        self.assertEqual(result["statusCode"], 401)

    def test_rejects_invalid_request_shape(self) -> None:
        event = _authed_event({"project": {}, "goal": {}, "strict": True})
        result = api_mix_resolve.handler(event, None)
        self.assertEqual(result["statusCode"], 400)
        self.assertIn("actions", result["body"])

    def test_rejects_contract_version_mismatch(self) -> None:
        event = _authed_event(
            {
                "project_state": {"rows": [], "max_rows": 8, "bpm": 120.0},
                "goal": {"type": "mix_request", "target": {"scope": "auto"}},
                "actions": [],
                "strict": True,
                "mix_feature_contract_version": "wrong-version",
            }
        )
        result = api_mix_resolve.handler(event, None)
        self.assertEqual(result["statusCode"], 400)
        self.assertIn("mix_feature_contract_version_mismatch", result["body"])

    def test_returns_refined_actions(self) -> None:
        fake_service = mock.Mock()
        fake_service.resolve.return_value = {
            "actions": [
                {
                    "type": "set_row_gain",
                    "data": {"row": 0, "delta": 0.2},
                }
            ],
            "debug_entries": [
                {
                    "action_index": 0,
                    "action_type": "set_row_gain",
                    "decision": "keep",
                    "dropped": False,
                }
            ],
            "observability": {
                "mix_magnitude_model_source": "remote",
                "mix_magnitude_model_bundle_version": "server-default",
                "mix_apply_model_version": "mix_apply_classifier_test",
                "mix_magnitude_regressor_version": "mix_magnitude_regressor_test",
                "mix_feature_contract_version": "mix_refine_v1",
            },
        }
        api_mix_resolve._resolver = fake_service

        event = _authed_event(
            {
                "project_state": {"rows": [], "max_rows": 8, "bpm": 120.0},
                "goal": {"type": "mix_request", "target": {"scope": "auto"}},
                "actions": [{"type": "set_row_gain", "data": {"row": 0, "delta": 0.5}}],
                "strict": True,
                "client_context": {"app_version": "1.1.2+23"},
            }
        )
        result = api_mix_resolve.handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        payload = json.loads(result["body"])
        self.assertEqual(payload["actions"][0]["type"], "set_row_gain")
        self.assertFalse(payload["fallback_used"])
        self.assertEqual(payload["fallback_reason"], "")
        self.assertEqual(
            payload["observability"]["mix_feature_contract_version"],
            "mix_refine_v1",
        )
        fake_service.resolve.assert_called_once()


def _authed_event(body: dict) -> dict:
    with mock.patch.object(auth_module, "_load_secret", return_value="secret"):
        token = _mint_test_token({"sub": "user-1", "sid": "session-1"})
    return {
        "headers": {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        "requestContext": {
            "http": {
                "method": "POST",
            },
            "routeKey": "POST /v1/mix/resolve",
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
            },
        },
        "rawPath": "/v1/mix/resolve",
        "body": json.dumps(body),
    }


def _mint_test_token(extra_claims: dict) -> str:
    header = _b64json({"alg": "HS256", "typ": "JWT"})
    payload = _b64json(
        {
            "iss": auth_module.config.APP_AUTH_ISSUER,
            "aud": auth_module.config.APP_AUTH_AUDIENCE,
            "exp": 4102444800,
            "token_use": "access",
            **extra_claims,
        }
    )
    signing_input = f"{header}.{payload}".encode("ascii")
    with mock.patch.object(auth_module, "_load_secret", return_value="secret"):
        signature = auth_module._sign(signing_input)  # noqa: SLF001
    return f"{header}.{payload}.{signature}"


def _b64json(payload: dict) -> str:
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("=")


if __name__ == "__main__":
    unittest.main()
