import importlib
import unittest
from unittest import mock

import support  # noqa: F401

module = importlib.import_module("src.common.provider_portals")


class ProviderPortalsTests(unittest.TestCase):
    def test_paddle_portal_session_parses_wrapped_response(self):
        original_secret_arn = module.config.PADDLE_API_KEY_SECRET_ARN
        module.config.PADDLE_API_KEY_SECRET_ARN = "paddle-api-key"
        try:
            with mock.patch.object(module, "load_provider_api_key", return_value="apikey_test"), mock.patch.object(
                module,
                "_post_json",
                return_value={
                    "data": {
                        "urls": {
                            "general": {
                                "overview": "https://customer-portal.paddle.com/overview",
                            },
                            "subscriptions": [
                                {
                                    "id": "sub_123",
                                    "cancel_subscription": "https://customer-portal.paddle.com/cancel",
                                    "update_subscription_payment_method": "https://customer-portal.paddle.com/update",
                                }
                            ],
                        }
                    }
                },
            ):
                payload = module.build_management_links(
                    provider="paddle",
                    customer_id="ctm_123",
                    subscription_id="sub_123",
                )
        finally:
            module.config.PADDLE_API_KEY_SECRET_ARN = original_secret_arn

        self.assertTrue(payload["configured"])
        self.assertEqual(
            payload["links"]["overview"],
            "https://customer-portal.paddle.com/overview",
        )
        self.assertEqual(
            payload["links"]["update_payment_method"],
            "https://customer-portal.paddle.com/update",
        )
        self.assertEqual(
            payload["links"]["cancel_subscription"],
            "https://customer-portal.paddle.com/cancel",
        )


if __name__ == "__main__":
    unittest.main()
