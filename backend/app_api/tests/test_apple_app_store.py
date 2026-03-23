import importlib
import unittest
from types import SimpleNamespace
from unittest import mock

from support import FakeBillingRepo

module = importlib.import_module("src.common.apple_app_store")


class AppleAppStoreTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeBillingRepo()

    def test_verify_apple_purchase_routes_signed_transactions(self):
        with mock.patch.object(
            module,
            "_verify_apple_signed_transaction",
            return_value={"provider_event_id": "apple:signed"},
        ) as signed, mock.patch.object(
            module,
            "_verify_apple_receipt",
            return_value={"provider_event_id": "apple:receipt"},
        ) as receipt:
            result = module.verify_apple_purchase(
                self.repo,
                transaction_payload="a.b.c",
                expected_user_id="user-1",
            )

        self.assertEqual(result["provider_event_id"], "apple:signed")
        signed.assert_called_once()
        receipt.assert_not_called()

    def test_verify_apple_purchase_routes_receipts(self):
        with mock.patch.object(
            module,
            "_verify_apple_signed_transaction",
            return_value={"provider_event_id": "apple:signed"},
        ) as signed, mock.patch.object(
            module,
            "_verify_apple_receipt",
            return_value={"provider_event_id": "apple:receipt"},
        ) as receipt:
            result = module.verify_apple_purchase(
                self.repo,
                transaction_payload="legacy-receipt-payload",
                expected_user_id="user-1",
            )

        self.assertEqual(result["provider_event_id"], "apple:receipt")
        receipt.assert_called_once()
        signed.assert_not_called()

    def test_verify_apple_notification_normalizes_and_links_customer(self):
        notification = SimpleNamespace(
            notificationUUID="notif-1",
            notificationType="DID_FAIL_TO_RENEW",
            subtype="GRACE_PERIOD",
            signedDate="2026-03-20T00:00:00+00:00",
            data=SimpleNamespace(
                signedTransactionInfo="tx-jws",
                signedRenewalInfo="renewal-jws",
            ),
        )
        transaction = SimpleNamespace(
            originalTransactionId="orig-1",
            transactionId="tx-1",
            productId="mixroom_pro_monthly",
            appAccountToken="user-1",
            purchaseDate="2026-03-19T00:00:00+00:00",
            expiresDate="2099-04-19T00:00:00+00:00",
            signedDate="2026-03-20T00:00:00+00:00",
            revocationDate=None,
        )
        renewal = SimpleNamespace(
            originalTransactionId="orig-1",
            productId="mixroom_pro_monthly",
            gracePeriodExpiresDate="2099-04-19T00:00:00+00:00",
        )
        verifier = mock.Mock()
        verifier.verify_and_decode_notification.return_value = notification
        verifier.verify_and_decode_signed_transaction.return_value = transaction
        verifier.verify_and_decode_renewal_info.return_value = renewal

        with mock.patch.object(module, "_signed_data_verifier", return_value=verifier):
            result = module.verify_apple_notification(
                self.repo,
                signed_payload="a.b.c",
            )

        self.assertEqual(result["provider_event_id"], "notif-1")
        self.assertEqual(result["normalized"]["status"], "grace_period")
        self.assertEqual(
            self.repo.get_customer_link("apple", "subscription:orig-1")["user_id"],
            "user-1",
        )

    def test_verify_receipt_with_fallback_uses_sandbox_on_21007(self):
        with mock.patch.object(
            module,
            "_post_json",
            side_effect=[
                {"status": 21007},
                {"status": 0, "receipt": {"in_app": []}},
            ],
        ):
            result = module._verify_receipt_with_fallback({"receipt-data": "abc"})

        self.assertEqual(result["status"], 0)

    def test_normalize_apple_status_maps_refund_and_expiry(self):
        self.assertEqual(
            module._normalize_apple_status(
                notification_type="REFUND",
                subtype="",
                expires_at=None,
                revocation_date=None,
            ),
            "refunded",
        )
        self.assertEqual(
            module._normalize_apple_status(
                notification_type="",
                subtype="",
                expires_at="2000-01-01T00:00:00+00:00",
                revocation_date=None,
            ),
            "expired",
        )


if __name__ == "__main__":
    unittest.main()
