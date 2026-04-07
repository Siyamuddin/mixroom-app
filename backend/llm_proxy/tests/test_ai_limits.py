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

        self.assertEqual(limits["prompt_limits"]["daily"], 50)
        self.assertEqual(limits["prompt_limits"]["weekly"], 350)
        self.assertEqual(limits["tiers"]["free"]["daily_credits"], 100)
        self.assertEqual(limits["feature_costs"]["stem_separation"], 30)
        self.assertEqual(limits["token_ratio"]["tokens_per_credit"], 500)

    def test_get_prompt_limits_reads_daily_and_weekly_caps(self) -> None:
        limits = ai_limits.get_prompt_limits()

        self.assertEqual(limits["daily_prompts"], 50)
        self.assertEqual(limits["weekly_prompts"], 350)

    def test_get_prompt_limits_prefers_remote_override_for_free_tier(self) -> None:
        with mock.patch.object(
            ai_limits,
            "_get_cached_remote_prompt_limits",
            return_value={
                "free_daily_prompt_limit": 12,
                "free_weekly_prompt_limit": 90,
            },
        ):
            limits = ai_limits.get_prompt_limits("free")

        self.assertEqual(limits["daily_prompts"], 12)
        self.assertEqual(limits["weekly_prompts"], 90)

    def test_get_prompt_limits_loads_remote_override_from_dynamodb(self) -> None:
        class _FakeTable:
            def get_item(self, **_kwargs):
                return {
                    "Item": {
                        "free_daily_prompt_limit": 100,
                        "free_weekly_prompt_limit": 500,
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

        self.assertEqual(limits["daily_prompts"], 100)
        self.assertEqual(limits["weekly_prompts"], 500)

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

        self.assertEqual(limits["daily_prompts"], 50)
        self.assertEqual(limits["weekly_prompts"], 350)

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

    def test_get_user_tier_maps_studio_to_pro_limits(self) -> None:
        tier = ai_limits.get_user_tier({"subscription_tier": "studio"})

        self.assertEqual(tier, "pro")

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
