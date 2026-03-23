import importlib
import unittest
from unittest import mock

from support import FakeBillingRepo

module = importlib.import_module("src.common.provider_support")


class ProviderSupportTests(unittest.TestCase):
    def test_assert_user_link_available_prefers_resolved_user(self):
        user_id = module.assert_user_link_available(
            resolved_user_id="user-1",
            expected_user_id="user-1",
            existing_link_user_id="user-1",
            provider="Apple",
        )

        self.assertEqual(user_id, "user-1")

    def test_assert_user_link_available_rejects_cross_account_purchase(self):
        with self.assertRaises(module.ProviderVerificationError) as ctx:
            module.assert_user_link_available(
                resolved_user_id="user-2",
                expected_user_id="user-1",
                provider="Google Play",
            )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("different Mixroom account", str(ctx.exception))

    def test_assert_user_link_available_requires_any_user(self):
        with self.assertRaises(module.ProviderVerificationError) as ctx:
            module.assert_user_link_available(
                resolved_user_id="",
                existing_link_user_id="",
                expected_user_id="",
                provider="Apple",
            )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("Unable to resolve Mixroom user", str(ctx.exception))

    def test_active_status_for_expiry_handles_refund_revoke_and_expiry(self):
        now = module.utc_now()
        with mock.patch.object(module, "utc_now", return_value=now):
            self.assertEqual(
                module.active_status_for_expiry(
                    expires_at=now.isoformat(),
                    revoked_at="2026-03-20T00:00:00+00:00",
                    refund=True,
                ),
                "refunded",
            )
            self.assertEqual(
                module.active_status_for_expiry(
                    expires_at=now.isoformat(),
                    revoked_at="2026-03-20T00:00:00+00:00",
                    refund=False,
                ),
                "revoked",
            )
            self.assertEqual(
                module.active_status_for_expiry(
                    expires_at="2999-01-01T00:00:00+00:00",
                ),
                "active",
            )
            self.assertEqual(
                module.active_status_for_expiry(
                    expires_at="2000-01-01T00:00:00+00:00",
                ),
                "expired",
            )

    def test_resolve_tier_for_product_uses_catalog_before_fallback(self):
        repo = FakeBillingRepo()
        repo.catalog_mappings["apple:mixroom_pro_monthly"] = {
            "provider_product_key": "apple:mixroom_pro_monthly",
            "tier": "studio",
        }

        self.assertEqual(
            module.resolve_tier_for_product(repo, "apple", "mixroom_pro_monthly"),
            "studio",
        )
        self.assertEqual(
            module.resolve_tier_for_product(
                repo,
                "apple",
                "mixroom_pro_monthly",
                fallback_tier="pro",
            ),
            "studio",
        )
        self.assertEqual(
            module.resolve_tier_for_product(
                repo,
                "google",
                "mixroom_pro_monthly",
                fallback_tier="pro",
            ),
            "pro",
        )


if __name__ == "__main__":
    unittest.main()
