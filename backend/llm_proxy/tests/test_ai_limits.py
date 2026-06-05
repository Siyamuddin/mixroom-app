from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import ai_limits  # noqa: E402


class AiLimitsTests(unittest.TestCase):
    def setUp(self) -> None:
        ai_limits.load_ai_limits.cache_clear()
        ai_limits.clear_prompt_limits_cache()

    def test_load_ai_limits_reads_expected_single_source_file(self) -> None:
        limits = ai_limits.load_ai_limits()

        self.assertEqual(limits["prompt_limits"]["free"]["daily"], 200)
        self.assertEqual(limits["prompt_limits"]["free"]["weekly"], 600)
        self.assertEqual(limits["prompt_limits"]["starter"]["daily"], 400)
        self.assertEqual(limits["prompt_limits"]["producer"]["daily"], 1000)
        self.assertEqual(limits["tiers"]["free"]["daily_credits"], 100)
        self.assertEqual(limits["feature_costs"]["stem_separation"], 30)
        self.assertEqual(limits["token_ratio"]["tokens_per_credit"], 500)

    def test_get_prompt_limits_reads_daily_and_weekly_caps(self) -> None:
        limits = ai_limits.get_prompt_limits()

        self.assertEqual(limits["daily_prompts"], 200)
        self.assertEqual(limits["weekly_prompts"], 600)

    def test_get_prompt_limits_reads_subscription_tiers(self) -> None:
        starter = ai_limits.get_prompt_limits("starter")
        producer = ai_limits.get_prompt_limits("producer")
        legacy_pro = ai_limits.get_prompt_limits("pro")
        education = ai_limits.get_prompt_limits("education")
        enterprise = ai_limits.get_prompt_limits("enterprise")

        self.assertEqual(starter["daily_prompts"], 400)
        self.assertEqual(starter["weekly_prompts"], 1500)
        self.assertEqual(education["daily_prompts"], 400)
        self.assertEqual(education["weekly_prompts"], 1500)
        self.assertEqual(producer["daily_prompts"], 1000)
        self.assertEqual(producer["weekly_prompts"], 4000)
        self.assertEqual(legacy_pro["daily_prompts"], 1000)
        self.assertEqual(legacy_pro["weekly_prompts"], 4000)
        self.assertEqual(enterprise["daily_prompts"], 1000)
        self.assertEqual(enterprise["weekly_prompts"], 4000)

    def test_get_prompt_limits_prefers_explicit_limit_overrides(self) -> None:
        limits = ai_limits.get_prompt_limits(
            "starter",
            {
                "ai_prompts_daily": 123,
                "ai_prompts_weekly": 456,
            },
        )

        self.assertEqual(limits["daily_prompts"], 123)
        self.assertEqual(limits["weekly_prompts"], 456)

    def test_get_prompt_limits_falls_back_when_limit_overrides_are_invalid(self) -> None:
        custom = ai_limits.get_prompt_limits(
            "producer",
            {
                "ai_prompts_daily": "custom",
                "ai_prompts_weekly": "custom",
            },
        )
        inverted = ai_limits.get_prompt_limits(
            "starter",
            {
                "ai_prompts_daily": 400,
                "ai_prompts_weekly": 100,
            },
        )

        self.assertEqual(custom["daily_prompts"], 1000)
        self.assertEqual(custom["weekly_prompts"], 4000)
        self.assertEqual(inverted["daily_prompts"], 400)
        self.assertEqual(inverted["weekly_prompts"], 1500)

    def test_get_prompt_limits_prefers_remote_override_for_free_tier(self) -> None:
        with mock.patch.object(
            ai_limits,
            "_get_cached_remote_prompt_limits",
            return_value={
                "free_daily_prompt_limit": 12,
                "free_weekly_prompt_limit": 90,
            },
        ):
            limits = ai_limits.get_prompt_limits(
                "free",
                {
                    "ai_prompts_daily": 100,
                    "ai_prompts_weekly": 500,
                },
            )

        self.assertEqual(limits["daily_prompts"], 12)
        self.assertEqual(limits["weekly_prompts"], 90)

    def test_get_prompt_limits_loads_remote_override_from_dynamodb(self) -> None:
        class _FakeTable:
            def get_item(self, **_kwargs):
                return {
                    "Item": {
                        "free_daily_prompt_limit": 123,
                        "free_weekly_prompt_limit": 456,
                    }
                }

        class _FakeDynamoResource:
            def Table(self, _name):
                return _FakeTable()

        fake_boto3 = mock.Mock()
        fake_boto3.resource.return_value = _FakeDynamoResource()

        with mock.patch.object(ai_limits, "boto3", fake_boto3), mock.patch.object(
            ai_limits.config,
            "AI_PROMPT_LIMIT_SETTINGS_TABLE",
            "mixroom-ai-prompt-limit-settings-prod",
        ):
            ai_limits.clear_prompt_limits_cache()
            limits = ai_limits.get_prompt_limits("free")

        self.assertEqual(limits["daily_prompts"], 123)
        self.assertEqual(limits["weekly_prompts"], 456)

    def test_get_prompt_limits_does_not_apply_free_override_to_pro_tier(self) -> None:
        with mock.patch.object(
            ai_limits,
            "_get_cached_remote_prompt_limits",
            return_value={
                "free_daily_prompt_limit": 12,
                "free_weekly_prompt_limit": 90,
            },
        ):
            limits = ai_limits.get_prompt_limits("pro")

        self.assertEqual(limits["daily_prompts"], 1000)
        self.assertEqual(limits["weekly_prompts"], 4000)

    def test_validate_feature_accepts_legacy_aliases(self) -> None:
        self.assertEqual(ai_limits.validate_feature("assistant_chat"), "ai_chat")
        self.assertEqual(ai_limits.validate_feature("one_button_mix"), "ai_chat")
        self.assertEqual(ai_limits.validate_feature("stem_separate"), "stem_separation")
        self.assertEqual(ai_limits.validate_feature("video_editor"), "video_editor_chat")

    def test_calculate_credit_cost_adds_base_feature_cost_and_token_cost(self) -> None:
        credits = ai_limits.calculate_credit_cost(
            feature="assistant_chat",
            promptTokens=320,
            completionTokens=180,
        )

        self.assertEqual(credits, 2)

    def test_get_user_tier_preserves_studio_plan(self) -> None:
        tier = ai_limits.get_user_tier({"subscription_tier": "studio"})

        self.assertEqual(tier, "studio")

    def test_apply_server_output_token_cap_sets_default_and_clamps_large_values(self) -> None:
        with mock.patch.dict(os.environ, {"LLM_MAX_OUTPUT_TOKENS": "256"}, clear=False):
            request_body = {"messages": [{"role": "user", "content": "hello"}]}
            ai_limits.apply_server_output_token_cap(request_body)
            self.assertEqual(request_body["max_output_tokens"], 256)

            request_body["max_output_tokens"] = 1024
            ai_limits.apply_server_output_token_cap(request_body)
            self.assertEqual(request_body["max_output_tokens"], 256)


if __name__ == "__main__":
    unittest.main()
