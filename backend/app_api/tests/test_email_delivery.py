from __future__ import annotations

import io
import json
import os
import sys
import unittest
import urllib.error
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

for key, value in {
    "BILLING_EVENTS_TABLE": "billing-events",
    "SUBSCRIPTIONS_TABLE": "subscriptions",
    "ENTITLEMENTS_TABLE": "entitlements",
    "CATALOG_MAPPINGS_TABLE": "catalog",
    "CUSTOMER_LINKS_TABLE": "customer-links",
    "PURCHASE_TOKENS_TABLE": "purchase-tokens",
    "RECONCILIATION_JOBS_TABLE": "reconciliation-jobs",
    "PROJECTION_QUEUE_URL": "https://example.com/queue",
    "USERS_TABLE": "users",
    "USERNAME_CLAIMS_TABLE": "username-claims",
    "AUTH_ACCOUNTS_TABLE": "auth-accounts",
    "AUTH_SESSIONS_TABLE": "auth-sessions",
    "APP_AUTH_SECRET_ARN": "app-auth-secret",
    "APP_AUTH_EMAIL_FROM_ADDRESS": "contact@mixroom.ai",
}.items():
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

    exceptions_stub.ClientError = _ClientError
    botocore_stub.exceptions = exceptions_stub
    sys.modules["botocore"] = botocore_stub
    sys.modules["botocore.exceptions"] = exceptions_stub

from src.common import email_delivery  # noqa: E402


class EmailDeliveryTests(unittest.TestCase):
    def test_send_auth_email_posts_to_postmark(self) -> None:
        class _Response:
            def __init__(self, payload: bytes) -> None:
                self._payload = payload

            def read(self) -> bytes:
                return self._payload

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

        with mock.patch.object(
            email_delivery.config,
            "APP_AUTH_EMAIL_FROM_ADDRESS",
            "contact@mixroom.ai",
        ), mock.patch.object(
            email_delivery.config,
            "APP_AUTH_EMAIL_REPLY_TO_ADDRESS",
            "contact@mixroom.ai",
        ), mock.patch.object(
            email_delivery.config,
            "POSTMARK_MESSAGE_STREAM",
            "outbound",
        ), mock.patch.object(
            email_delivery,
            "load_postmark_server_token",
            return_value="postmark-token",
        ), mock.patch.object(
            email_delivery.urllib.request,
            "urlopen",
            return_value=_Response(
                b'{"ErrorCode":0,"Message":"OK","MessageID":"msg-123"}'
            ),
        ) as urlopen:
            email_delivery.send_auth_email(
                to_email="user@example.com",
                subject="Verify your Mixroom account",
                text_body="Code: 123456",
                html_body="<p>Code: <b>123456</b></p>",
            )

        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_full_url(), "https://api.postmarkapp.com/email")
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.get_header("X-postmark-server-token"), "postmark-token")
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual(payload["From"], "contact@mixroom.ai")
        self.assertEqual(payload["To"], "user@example.com")
        self.assertEqual(payload["ReplyTo"], "contact@mixroom.ai")
        self.assertEqual(payload["MessageStream"], "outbound")
        self.assertEqual(payload["Subject"], "Verify your Mixroom account")
        self.assertEqual(payload["TextBody"], "Code: 123456")
        self.assertEqual(payload["HtmlBody"], "<p>Code: <b>123456</b></p>")

    def test_send_auth_email_raises_suppressed_for_inactive_recipient(self) -> None:
        body = io.BytesIO(b'{"ErrorCode":406,"Message":"Inactive recipient"}')
        http_error = urllib.error.HTTPError(
            url="https://api.postmarkapp.com/email",
            code=422,
            msg="Unprocessable Entity",
            hdrs=None,
            fp=body,
        )
        with mock.patch.object(
            email_delivery.config,
            "APP_AUTH_EMAIL_FROM_ADDRESS",
            "contact@mixroom.ai",
        ), mock.patch.object(
            email_delivery,
            "load_postmark_server_token",
            return_value="postmark-token",
        ), mock.patch.object(
            email_delivery.urllib.request,
            "urlopen",
            side_effect=http_error,
        ):
            with self.assertRaises(email_delivery.EmailSuppressedError):
                email_delivery.send_auth_email(
                    to_email="inactive@example.com",
                    subject="Verify your Mixroom account",
                    text_body="Code: 123456",
                )


if __name__ == "__main__":
    unittest.main()
