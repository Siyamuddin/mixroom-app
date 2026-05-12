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

    def test_resolve_access_for_product_uses_mapping_before_fallback(self):
        repo = FakeBillingRepo()
        repo.catalog_mappings["apple:mixroom_pro_monthly"] = {
            "provider_product_key": "apple:mixroom_pro_monthly",
            "plan_code": "studio",
            "product_code": "studio_monthly",
        }

        access = module.resolve_access_for_product(
            repo,
            "apple",
            "mixroom_pro_monthly",
        )
        self.assertEqual(
            access,
            {"plan_code": "studio", "product_code": "studio_monthly"},
        )
        self.assertEqual(
            module.resolve_access_for_product(
                repo,
                "google",
                "mixroom_producer_monthly",
                fallback_plan_code="producer",
            ),
            {"plan_code": "producer", "product_code": "producer_monthly"},
        )
        self.assertEqual(
            module.resolve_access_for_product(
                repo,
                "google",
                "mixroom_pro_monthly",
            )["plan_code"],
            "producer",
        )

    def test_resolve_access_for_product_preserves_mapped_plan_code(self):
        repo = FakeBillingRepo()
        repo.catalog_mappings["apple:mixroom_starter_monthly"] = {
            "provider_product_key": "apple:mixroom_starter_monthly",
            "plan_code": "starter",
            "product_code": "starter_monthly",
        }

        access = module.resolve_access_for_product(
            repo,
            "apple",
            "mixroom_starter_monthly",
        )

        self.assertEqual(access["plan_code"], "starter")
        self.assertEqual(access["product_code"], "starter_monthly")

    def test_resolve_access_for_product_preserves_custom_mapped_plan_code(self):
        repo = FakeBillingRepo()
        repo.catalog_mappings["paddle:mixroom_founder_monthly"] = {
            "provider_product_key": "paddle:mixroom_founder_monthly",
            "plan_code": "founder",
            "product_code": "founder_monthly",
        }

        access = module.resolve_access_for_product(
            repo,
            "paddle",
            "mixroom_founder_monthly",
        )

        self.assertEqual(access["plan_code"], "founder")
        self.assertEqual(access["product_code"], "founder_monthly")

    def test_resolve_access_for_product_rejects_disabled_provider_product(self):
        repo = FakeBillingRepo()
        catalog = {
            "plans": [{"code": "producer", "label": "Producer"}],
            "products": [
                {
                    "code": "producer_monthly",
                    "plan_code": "producer",
                    "enabled": True,
                }
            ],
            "provider_products": [
                {
                    "provider": "apple",
                    "provider_product_id": "mixroom_producer_monthly",
                    "product_code": "producer_monthly",
                    "enabled": False,
                }
            ],
        }

        with mock.patch(
            "src.common.billing_catalog_repository.BillingCatalogRepository",
            return_value=mock.Mock(get_catalog=mock.Mock(return_value=catalog)),
        ):
            with self.assertRaises(module.ProviderVerificationError) as ctx:
                module.resolve_access_for_product(
                    repo,
                    "apple",
                    "mixroom_producer_monthly",
                )

        self.assertEqual(ctx.exception.status_code, 409)

    def test_resolve_access_for_product_rejects_disabled_catalog_product(self):
        repo = FakeBillingRepo()
        catalog = {
            "plans": [{"code": "producer", "label": "Producer"}],
            "products": [
                {
                    "code": "producer_monthly",
                    "plan_code": "producer",
                    "enabled": False,
                }
            ],
            "provider_products": [
                {
                    "provider": "google",
                    "provider_product_id": "mixroom_producer_monthly",
                    "product_code": "producer_monthly",
                    "enabled": True,
                }
            ],
        }

        with mock.patch(
            "src.common.billing_catalog_repository.BillingCatalogRepository",
            return_value=mock.Mock(get_catalog=mock.Mock(return_value=catalog)),
        ):
            with self.assertRaises(module.ProviderVerificationError) as ctx:
                module.resolve_access_for_product(
                    repo,
                    "google",
                    "mixroom_producer_monthly",
                )

        self.assertEqual(ctx.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
