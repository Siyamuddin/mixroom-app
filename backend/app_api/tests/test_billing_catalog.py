import unittest

import support  # noqa: F401
from src.common.billing_catalog import (
    default_catalog,
    infer_plan_code,
    merge_limits,
    normalize_catalog_payload,
)
from src.common.models import default_capabilities_for_plan, default_limits_for_plan
from src.common.plan_catalog import PLAN_CATALOG


class BillingCatalogTests(unittest.TestCase):
    def test_infer_plan_code_preserves_known_custom_plan_code(self):
        self.assertEqual(
            infer_plan_code("founder", known_plan_codes={"free", "founder"}),
            "founder",
        )

    def test_normalize_catalog_payload_allows_custom_product_plan_code(self):
        catalog = normalize_catalog_payload(
            plans=[
                {
                    "code": "free",
                    "label": "Free",
                },
                {
                    "code": "founder",
                    "label": "Founder",
                },
            ],
            products=[
                {
                    "code": "founder_monthly",
                    "plan_code": "founder",
                    "type": "subscription",
                    "billing_interval": "monthly",
                }
            ],
            provider_products=[],
            support={},
        )

        self.assertEqual(catalog["products"][0]["plan_code"], "founder")

    def test_default_catalog_uses_producer_store_product_ids(self):
        provider_product_ids = {
            item["provider_product_id"]
            for item in default_catalog()["provider_products"]
            if item["product_code"] == "producer_monthly"
        }

        self.assertNotIn("mixroom_pro_monthly", provider_product_ids)
        self.assertIn("mixroom_producer_monthly", provider_product_ids)

    def test_default_catalog_uses_shared_plan_catalog_source(self):
        plans = {item["code"]: item for item in default_catalog()["plans"]}

        self.assertEqual(
            plans["starter"]["description"],
            PLAN_CATALOG["starter"]["description"],
        )
        self.assertEqual(
            plans["producer"]["capabilities"],
            default_capabilities_for_plan("producer"),
        )
        self.assertEqual(plans["studio"]["limits"], default_limits_for_plan("studio"))

    def test_merge_limits_preserves_unlimited_plan_limit_over_free_baseline(self):
        merged = merge_limits(
            {"cloud_projects": 3, "storage_gb": 0.25},
            {"cloud_projects": "custom", "storage_gb": 5},
        )

        self.assertEqual(merged["cloud_projects"], "custom")
        self.assertEqual(merged["storage_gb"], 5)

    def test_education_seats_use_starter_level_creative_entitlements(self):
        plans = {item["code"]: item for item in default_catalog()["plans"]}
        education = plans["education"]
        starter = plans["starter"]

        starter_capability_keys = {
            "all_plugins",
            "high_quality_export",
            "wav_starter_samples",
            "selectable_ai_models",
            "advanced_ai_models",
            "premium_sound_libraries",
            "cloud_file_browser",
            "custom_sample_packs",
        }
        for key in starter_capability_keys:
            self.assertEqual(
                education["capabilities"].get(key),
                starter["capabilities"].get(key),
                key,
            )
        for key in (
            "storage_gb",
            "platform_upload_hours",
            "ai_prompts_daily",
            "ai_prompts_weekly",
            "ai_model_tier",
        ):
            self.assertEqual(education["limits"].get(key), starter["limits"].get(key), key)
        self.assertEqual(education["limits"]["seat_options"], [10, 20, 30])
        self.assertTrue(education["capabilities"]["education_sandbox"])
        self.assertTrue(education["capabilities"]["compliance_controls"])

    def test_default_catalog_matches_launch_product_scope(self):
        catalog = default_catalog()
        products = {item["code"]: item for item in catalog["products"]}
        provider_products = {
            (item["provider"], item["product_code"], item["provider_product_id"])
            for item in catalog["provider_products"]
        }

        self.assertTrue(products["studio_monthly"]["enabled"])
        self.assertTrue(products["studio_yearly"]["enabled"])
        self.assertEqual(
            products["studio_monthly"]["management_channel"],
            "web",
        )
        self.assertEqual(products["studio_monthly"]["platforms"], ["web"])
        self.assertFalse(products["credits_100"]["enabled"])
        self.assertFalse(products["day_pass"]["enabled"])
        self.assertNotIn(("apple", "studio_monthly", "mixroom_studio_monthly"), provider_products)
        self.assertNotIn(("google", "studio_yearly", "mixroom_studio_yearly"), provider_products)
        self.assertIn(("paddle", "studio_monthly", "mixroom_studio_monthly"), provider_products)

    def test_normalize_catalog_payload_rejects_unknown_product_plan_code(self):
        with self.assertRaises(ValueError):
            normalize_catalog_payload(
                plans=[{"code": "free", "label": "Free"}],
                products=[
                    {
                        "code": "mystery_monthly",
                        "plan_code": "mystery",
                        "type": "subscription",
                        "billing_interval": "monthly",
                    }
                ],
                provider_products=[],
                support={},
            )


if __name__ == "__main__":
    unittest.main()
