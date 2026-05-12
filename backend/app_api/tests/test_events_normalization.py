import unittest

import support  # noqa: F401
from src.common.events import normalize_webhook


class EventsNormalizationTests(unittest.TestCase):
    def test_web_checkout_provider_webhook_preserves_plan_metadata(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "id": "sub-1",
                "status": "active",
                "metadata": {
                    "mixroom_user_id": "user-1",
                    "plan_code": "starter",
                    "product_code": "starter_monthly",
                    "provider_product_id": "mixroom_starter_monthly",
                },
            },
        )

        self.assertEqual(normalized["plan_code"], "starter")
        self.assertEqual(normalized["product_code"], "starter_monthly")
        self.assertEqual(normalized["product_id"], "mixroom_starter_monthly")

    def test_webhook_maps_legacy_pro_tier_to_producer_plan(self):
        normalized = normalize_webhook(
            "paddle",
            {
                "id": "sub-1",
                "status": "active",
                "metadata": {
                    "mixroom_user_id": "user-1",
                    "tier": "pro",
                    "provider_product_id": "mixroom_pro_monthly",
                },
            },
        )

        self.assertEqual(normalized["plan_code"], "producer")


if __name__ == "__main__":
    unittest.main()
