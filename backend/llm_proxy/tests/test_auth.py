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


class _FakeTable:
    def __init__(self, items=None) -> None:
        self.items = dict(items or {})

    def get_item(self, *, Key):
        key_name, key_value = next(iter(Key.items()))
        return {"Item": self.items.get(key_value)} if key_value in self.items else {}

    def delete_item(self, *, Key):
        _, key_value = next(iter(Key.items()))
        self.items.pop(key_value, None)


class ProxyAuthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_sessions = auth_module._auth_sessions
        self.original_accounts = auth_module._auth_accounts
        self.original_app_auth_secret = auth_module.config.APP_AUTH_SECRET_ARN
        auth_module.config.APP_AUTH_SECRET_ARN = "app-auth-secret"

    def tearDown(self) -> None:
        auth_module._auth_sessions = self.original_sessions
        auth_module._auth_accounts = self.original_accounts
        auth_module.config.APP_AUTH_SECRET_ARN = self.original_app_auth_secret

    def test_extract_claims_requires_live_session(self) -> None:
        auth_module._auth_sessions = _FakeTable(
            {
                "session-1": {
                    "session_id": "session-1",
                    "user_id": "user-1",
                    "expires_at": "2099-01-01T00:00:00+00:00",
                }
            }
        )
        auth_module._auth_accounts = _FakeTable({"user-1": {"user_id": "user-1"}})

        with mock.patch.object(auth_module, "_load_secret", return_value="secret"):
            token = _mint_test_token({"sub": "user-1", "sid": "session-1"})
            claims = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": f"Bearer {token}"}}
            )

        self.assertEqual(claims["sub"], "user-1")

    def test_extract_claims_rejects_missing_session(self) -> None:
        auth_module._auth_sessions = _FakeTable()
        auth_module._auth_accounts = _FakeTable({"user-1": {"user_id": "user-1"}})

        with mock.patch.object(auth_module, "_load_secret", return_value="secret"):
            token = _mint_test_token({"sub": "user-1", "sid": "session-1"})
            claims = auth_module.extract_claims_from_event(
                {"headers": {"Authorization": f"Bearer {token}"}}
            )

        self.assertEqual(claims, {})

    def test_extract_claims_rejects_non_native_authorizer_claims(self) -> None:
        claims = auth_module.extract_claims_from_event(
            {
                "requestContext": {
                    "authorizer": {
                        "jwt": {
                            "claims": {
                                "iss": "https://cognito-idp.ap-northeast-2.amazonaws.com/pool-id",
                                "aud": "client-id",
                                "sub": "legacy-user",
                                "token_use": "access",
                            }
                        }
                    }
                }
            }
        )

        self.assertEqual(claims, {})


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
