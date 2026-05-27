import unittest
from unittest import mock

import support  # noqa: F401
from src.common.repository import BillingRepository


class BillingRepositoryTests(unittest.TestCase):
    def test_upsert_subscription_omits_null_expires_at_index_key(self):
        repository = BillingRepository.__new__(BillingRepository)
        repository._subscriptions = mock.Mock()

        repository.upsert_subscription(
            {
                "subscription_id": "sub-1",
                "user_id": "user-1",
                "status": "active",
                "expires_at": None,
            }
        )

        written = repository._subscriptions.put_item.call_args.kwargs["Item"]
        self.assertNotIn("expires_at", written)
        self.assertEqual(written["status_key"], "active")


if __name__ == "__main__":
    unittest.main()
