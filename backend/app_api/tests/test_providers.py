import importlib
import unittest
from unittest import mock

import support  # noqa: F401

module = importlib.import_module("src.common.providers")


class ProvidersTests(unittest.TestCase):
    def test_choose_web_provider_routes_kr_to_toss(self):
        self.assertEqual(module.choose_web_provider("KR"), "toss")
        self.assertEqual(module.choose_web_provider("US"), "paddle")

    def test_verify_webhook_signature_for_paddle(self):
        body = '{"id":"evt-1"}'
        secret = "secret-key"
        timestamp = 1700000000
        with mock.patch.object(module.config, "PADDLE_WEBHOOK_SECRET_ARN", "arn:secret"), mock.patch.object(
            module,
            "load_webhook_secret",
            return_value=secret,
        ), mock.patch.object(
            module.time,
            "time",
            return_value=timestamp,
        ):
            good_signature = module.hmac.new(
                secret.encode("utf-8"),
                f"{timestamp}:{body}".encode("utf-8"),
                module.hashlib.sha256,
            ).hexdigest()
            self.assertTrue(
                module.verify_webhook_signature(
                    "paddle",
                    {"Paddle-Signature": f"ts={timestamp};h1={good_signature}"},
                    body,
                )
            )
            self.assertFalse(
                module.verify_webhook_signature(
                    "paddle",
                    {"Paddle-Signature": f"ts={timestamp};h1=bad"},
                    body,
                )
            )

    def test_verify_toss_webhook_rejects_unsigned_payment_fetch_fallback(self):
        body = (
            '{"eventType":"PAYMENT_STATUS_CHANGED",'
            '"data":{"paymentKey":"pay-1","orderId":"order-1","status":"DONE","totalAmount":149000}}'
        )
        with mock.patch.object(module.config, "TOSS_WEBHOOK_SECRET_ARN", ""), mock.patch.object(
            module.config,
            "TOSS_SECRET_KEY_SECRET_ARN",
            "arn:toss-key",
        ), mock.patch.object(
            module,
            "retrieve_toss_payment",
            return_value={"paymentKey": "pay-1", "orderId": "order-1", "status": "DONE", "totalAmount": 149000},
        ) as retrieve:
            self.assertFalse(module.verify_webhook_signature("toss", {}, body))
            retrieve.assert_not_called()

    def test_portal_urls_match_provider(self):
        self.assertIn("apple.com", module.portal_url("apple"))
        self.assertIn("play.google.com", module.portal_url("google"))
        self.assertIn("paddle.com", module.portal_url("paddle"))
        self.assertIn("toss.im", module.portal_url("toss"))
        self.assertIn("mixroom.ai", module.portal_url("unknown"))


if __name__ == "__main__":
    unittest.main()
