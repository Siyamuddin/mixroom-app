import importlib
import json
import unittest

import support  # noqa: F401
from common.email_delivery import EmailDeliveryError


def _event(method="POST", body=None, origin="https://www.mixroom.ai"):
    headers = {}
    if origin:
        headers["origin"] = origin
    return {
        "rawPath": "/v1/contact",
        "requestContext": {
            "http": {"method": method, "sourceIp": "203.0.113.10"},
            "identity": {"sourceIp": "203.0.113.10"},
        },
        "headers": headers,
        "body": json.dumps(body or {}),
    }


class FakeRateLimiter:
    def enforce(self, **_kwargs):
        return type("Decision", (), {"allowed": True, "retry_after_seconds": 0})()


class ContactApiTest(unittest.TestCase):
    def setUp(self):
        self.api_contact = importlib.import_module("handlers.api_contact")
        self.sent = []
        self.original_sender = self.api_contact.send_postmark_email
        self.original_rate_limiter = self.api_contact.rate_limiter
        self.api_contact.rate_limiter = FakeRateLimiter()

        def fake_send(**kwargs):
            self.sent.append(kwargs)

        self.api_contact.send_postmark_email = fake_send

    def tearDown(self):
        self.api_contact.send_postmark_email = self.original_sender
        self.api_contact.rate_limiter = self.original_rate_limiter

    def test_options_echoes_allowed_origin(self):
        response = self.api_contact.handler(_event(method="OPTIONS"), None)

        self.assertEqual(response["statusCode"], 204)
        self.assertEqual(
            response["headers"]["Access-Control-Allow-Origin"],
            "https://www.mixroom.ai",
        )
        self.assertEqual(response["headers"]["Access-Control-Allow-Methods"], "POST,OPTIONS")

    def test_contact_submission_routes_to_contact_inbox(self):
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "contact",
                    "subject": "Partnership question",
                    "message": "Can we talk?",
                    "email": "visitor@example.com",
                    "pageUrl": "https://www.mixroom.ai/contact",
                    "locale": "en",
                }
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(json.loads(response["body"]), {"ok": True})
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.sent[0]["from_email"], "fromcontactpage@mixroom.ai")
        self.assertEqual(self.sent[0]["to_email"], "contact@mixroom.ai")
        self.assertEqual(self.sent[0]["reply_to_email"], "visitor@example.com")
        self.assertEqual(self.sent[0]["subject"], "Partnership question")
        self.assertIn("Can we talk?", self.sent[0]["text_body"])
        self.assertIn("Page URL: https://www.mixroom.ai/contact", self.sent[0]["text_body"])
        self.assertIn("Locale: en", self.sent[0]["text_body"])

    def test_support_submission_routes_to_support_inbox(self):
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "support",
                    "subject": "Billing problem",
                    "message": "I need help.",
                    "email": "visitor@example.com",
                    "pageUrl": "https://www.mixroom.ai/support",
                    "locale": "ko",
                },
                origin="https://mixroom.ai",
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(self.sent[0]["from_email"], "fromsupportpage@mixroom.ai")
        self.assertEqual(self.sent[0]["to_email"], "support@mixroom.ai")
        self.assertEqual(
            response["headers"]["Access-Control-Allow-Origin"],
            "https://mixroom.ai",
        )

    def test_rejects_invalid_source(self):
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "sales",
                    "subject": "Hello",
                    "message": "Message",
                    "email": "visitor@example.com",
                }
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.sent, [])

    def test_rejects_invalid_reply_to_email(self):
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "contact",
                    "subject": "Hello",
                    "message": "Message",
                    "email": "visitor@example.com\nbcc@example.com",
                }
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(self.sent, [])

    def test_rejects_disallowed_browser_origin(self):
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "contact",
                    "subject": "Hello",
                    "message": "Message",
                    "email": "visitor@example.com",
                },
                origin="https://evil.example",
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 403)
        self.assertEqual(self.sent, [])
        self.assertNotIn("Access-Control-Allow-Origin", response["headers"])

    def test_delivery_failure_returns_non_2xx(self):
        def failing_send(**_kwargs):
            raise EmailDeliveryError("boom")

        self.api_contact.send_postmark_email = failing_send
        response = self.api_contact.handler(
            _event(
                body={
                    "source": "contact",
                    "subject": "Hello",
                    "message": "Message",
                    "email": "visitor@example.com",
                }
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 502)


if __name__ == "__main__":
    unittest.main()
