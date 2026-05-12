import importlib
import base64
import json
import unittest
from datetime import datetime, timezone
from enum import Enum
from types import SimpleNamespace
from unittest import mock

from support import FakeBillingRepo

module = importlib.import_module("src.common.apple_app_store")


def _unsigned_jws(payload):
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode(
        "utf-8"
    )
    return f"header.{encoded.rstrip('=')}.signature"


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
            productId="mixroom_producer_monthly",
            appAccountToken="user-1",
            purchaseDate="2026-03-19T00:00:00+00:00",
            expiresDate="2099-04-19T00:00:00+00:00",
            signedDate="2026-03-20T00:00:00+00:00",
            revocationDate=None,
        )
        renewal = SimpleNamespace(
            originalTransactionId="orig-1",
            productId="mixroom_producer_monthly",
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

    def test_signed_purchase_reclaims_expired_subscription_link_for_current_user(self):
        self.repo.put_customer_link(
            "apple",
            "subscription:orig-1",
            "old-user",
            {"product_id": "mixroom_producer_monthly"},
        )
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "producer",
                "status": "expired",
                "source_provider": "apple",
                "source_subscription_id": "orig-1",
                "capabilities": {},
                "management_channel": "apple",
                "revision": 3,
            }
        )
        self.repo.upsert_subscription(
            {
                "subscription_id": "orig-1",
                "user_id": "old-user",
                "provider": "apple",
                "plan_code": "producer",
                "status": "expired",
                "expires_at": "2026-01-01T00:00:00+00:00",
            }
        )
        transaction = SimpleNamespace(
            originalTransactionId="orig-1",
            transactionId="tx-2",
            productId="mixroom_producer_monthly",
            appAccountToken="new-user",
            purchaseDate="2026-03-19T00:00:00+00:00",
            expiresDate="2099-04-19T00:00:00+00:00",
            signedDate="2026-03-20T00:00:00+00:00",
            revocationDate=None,
        )
        verifier = mock.Mock()
        verifier.verify_and_decode_signed_transaction.return_value = transaction

        with mock.patch.object(module, "_resolve_signed_environment", return_value="SANDBOX"), mock.patch.object(
            module, "_signed_data_verifier", return_value=verifier
        ):
            result = module._verify_apple_signed_transaction(
                self.repo,
                signed_transaction="a.b.c",
                expected_user_id="new-user",
                client_product_id="",
                client_app_account_token="",
            )

        self.assertEqual(result["user_id"], "new-user")
        self.assertEqual(result["normalized"]["reclaimed_from_user_id"], "old-user")
        self.assertEqual(
            self.repo.get_customer_link("apple", "subscription:orig-1")["user_id"],
            "new-user",
        )

    def test_signed_purchase_blocks_reclaim_when_old_subscription_has_access(self):
        self.repo.put_customer_link(
            "apple",
            "subscription:orig-1",
            "old-user",
            {"product_id": "mixroom_producer_monthly"},
        )
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2099-04-19T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "orig-1",
                "capabilities": {},
                "management_channel": "apple",
                "revision": 3,
            }
        )
        transaction = SimpleNamespace(
            originalTransactionId="orig-1",
            transactionId="tx-2",
            productId="mixroom_producer_monthly",
            appAccountToken="new-user",
            purchaseDate="2026-03-19T00:00:00+00:00",
            expiresDate="2099-04-19T00:00:00+00:00",
            signedDate="2026-03-20T00:00:00+00:00",
            revocationDate=None,
        )
        verifier = mock.Mock()
        verifier.verify_and_decode_signed_transaction.return_value = transaction

        with mock.patch.object(module, "_resolve_signed_environment", return_value="SANDBOX"), mock.patch.object(
            module, "_signed_data_verifier", return_value=verifier
        ):
            with self.assertRaises(module.ProviderVerificationError) as ctx:
                module._verify_apple_signed_transaction(
                    self.repo,
                    signed_transaction="a.b.c",
                    expected_user_id="new-user",
                    client_product_id="",
                    client_app_account_token="",
                )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("already linked", str(ctx.exception))

    def test_signed_purchase_client_verify_can_reclaim_webhook_reactivated_link(self):
        self.repo.put_customer_link(
            "apple",
            "subscription:orig-1",
            "old-user",
            {"product_id": "mixroom_producer_monthly"},
        )
        self.repo.put_entitlement(
            {
                "user_id": "old-user",
                "plan_code": "producer",
                "status": "active",
                "expires_at": "2099-04-19T00:00:00+00:00",
                "source_provider": "apple",
                "source_subscription_id": "orig-1",
                "capabilities": {},
                "management_channel": "apple",
                "revision": 3,
            }
        )
        transaction = SimpleNamespace(
            originalTransactionId="orig-1",
            transactionId="tx-2",
            productId="mixroom_producer_monthly",
            appAccountToken="old-user",
            purchaseDate="2026-03-19T00:00:00+00:00",
            expiresDate="2099-04-19T00:00:00+00:00",
            signedDate="2026-03-20T00:00:00+00:00",
            revocationDate=None,
        )
        verifier = mock.Mock()
        verifier.verify_and_decode_signed_transaction.return_value = transaction

        with mock.patch.object(module, "_resolve_signed_environment", return_value="SANDBOX"), mock.patch.object(
            module, "_signed_data_verifier", return_value=verifier
        ):
            result = module._verify_apple_signed_transaction(
                self.repo,
                signed_transaction="a.b.c",
                expected_user_id="new-user",
                client_product_id="",
                client_app_account_token="new-user",
            )

        self.assertEqual(result["user_id"], "new-user")
        self.assertEqual(result["normalized"]["reclaimed_from_user_id"], "old-user")
        self.assertEqual(
            self.repo.get_customer_link("apple", "subscription:orig-1")["user_id"],
            "new-user",
        )

    def test_signed_bundle_id_uses_matching_allowed_bundle(self):
        signed = _unsigned_jws(
            {
                "environment": "Sandbox",
                "data": {
                    "bundleId": "com.mixroom.mixroomapp",
                },
            }
        )

        with mock.patch.object(module.config, "APPLE_BUNDLE_ID", "ai.mixroom.web,com.mixroom.mixroomapp"):
            bundle_id = module._resolve_signed_bundle_id(signed)

        self.assertEqual(bundle_id, "com.mixroom.mixroomapp")

    def test_signed_bundle_id_reads_nested_transaction_bundle(self):
        transaction = _unsigned_jws({"bundleId": "com.mixroom.mixroomapp"})
        signed = _unsigned_jws(
            {
                "environment": "Sandbox",
                "data": {
                    "signedTransactionInfo": transaction,
                },
            }
        )

        with mock.patch.object(module.config, "APPLE_BUNDLE_ID", "ai.mixroom.web,com.mixroom.mixroomapp"):
            bundle_id = module._resolve_signed_bundle_id(signed)

        self.assertEqual(bundle_id, "com.mixroom.mixroomapp")

    def test_to_plain_dict_recursively_sanitizes_notification_payload(self):
        class NotificationKind(Enum):
            DID_RENEW = "DID_RENEW"

        payload = SimpleNamespace(
            notificationType=NotificationKind.DID_RENEW,
            signedDate=datetime(2026, 5, 5, tzinfo=timezone.utc),
            data=SimpleNamespace(
                nested={
                    "events": [
                        SimpleNamespace(
                            amount=1.25,
                            createdAt=datetime(2026, 5, 5, tzinfo=timezone.utc),
                        )
                    ]
                }
            ),
        )

        plain = module._to_plain_dict(payload)

        json.dumps(plain)
        self.assertEqual(plain["notificationType"], "DID_RENEW")
        self.assertEqual(plain["data"]["nested"]["events"][0]["amount"], "1.25")

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
