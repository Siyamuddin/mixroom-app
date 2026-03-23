from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

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
}.items():
    os.environ.setdefault(key, value)

from src.common import events as events_module  # noqa: E402


class EventParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_max_bytes = events_module.config.APP_API_MAX_REQUEST_BYTES

    def tearDown(self) -> None:
        events_module.config.APP_API_MAX_REQUEST_BYTES = self.original_max_bytes

    def test_parse_json_body_rejects_oversized_payload(self) -> None:
        events_module.config.APP_API_MAX_REQUEST_BYTES = 8

        with self.assertRaises(events_module.RequestPayloadTooLargeError):
            events_module.parse_json_body({"body": '{"username":"mixroomer"}'})

    def test_parse_json_body_requires_object_payload(self) -> None:
        with self.assertRaises(events_module.RequestBodyError):
            events_module.parse_json_body({"body": '["not","an","object"]'})


if __name__ == "__main__":
    unittest.main()
