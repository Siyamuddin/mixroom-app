from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import ai_runtime_config  # noqa: E402


class AiRuntimeConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        ai_runtime_config.clear_ai_runtime_cache()

    def test_ignores_invalid_remote_runtime_values(self) -> None:
        with mock.patch.object(
            ai_runtime_config,
            "_get_cached_runtime_item",
            return_value={
                "model_override": "bad-model",
                "reasoning_effort_override": "extreme",
                "prompt_cache_retention_override": "forever",
                "temperature_override": 0.7,
                "max_output_tokens_override": 2048,
                "system_prompt_override": "Remote prompt",
            },
        ):
            runtime = ai_runtime_config.get_ai_feature_runtime(
                "ai_chat",
                fallback_model="gpt-4.1-mini",
            )

        self.assertEqual(runtime["model"], "gpt-4.1-mini")
        self.assertFalse(runtime["has_model_override"])
        self.assertEqual(runtime["prompt_cache_retention"], "in_memory")
        self.assertFalse(runtime["has_prompt_cache_retention_override"])
        self.assertIsNone(runtime["reasoning"])
        self.assertFalse(runtime["has_reasoning_override"])
        self.assertEqual(runtime["temperature"], 0.7)
        self.assertTrue(runtime["has_temperature_override"])
        self.assertEqual(runtime["max_output_tokens"], 2048)
        self.assertTrue(runtime["has_max_output_tokens_override"])
        self.assertEqual(runtime["system_prompt"], "Remote prompt")
        self.assertTrue(runtime["has_system_prompt_override"])

    def test_applies_allowlisted_remote_runtime_values(self) -> None:
        with mock.patch.object(
            ai_runtime_config,
            "_get_cached_runtime_item",
            return_value={
                "model_override": "gpt-5-mini",
                "reasoning_effort_override": "medium",
                "prompt_cache_retention_override": "24h",
            },
        ):
            runtime = ai_runtime_config.get_ai_feature_runtime(
                "ai_chat",
                fallback_model="gpt-4.1-mini",
            )

        self.assertEqual(runtime["model"], "gpt-5-mini")
        self.assertTrue(runtime["has_model_override"])
        self.assertEqual(runtime["reasoning"], {"effort": "medium"})
        self.assertTrue(runtime["has_reasoning_override"])
        self.assertEqual(runtime["prompt_cache_retention"], "24h")
        self.assertTrue(runtime["has_prompt_cache_retention_override"])

    def test_default_runtime_uses_shared_default_helpers(self) -> None:
        with mock.patch.object(
            ai_runtime_config,
            "CHAT_DEFAULT_TEMPERATURE",
            0.35,
        ), mock.patch.object(
            ai_runtime_config,
            "default_reasoning",
            return_value={"effort": "minimal"},
        ), mock.patch.object(
            ai_runtime_config,
            "default_prompt_cache_retention",
            return_value="24h",
        ):
            runtime = ai_runtime_config.get_ai_feature_runtime(
                "ai_chat",
                fallback_model="gpt-5.2",
            )

        self.assertEqual(runtime["temperature"], 0.35)
        self.assertEqual(runtime["reasoning"], {"effort": "minimal"})
        self.assertEqual(runtime["prompt_cache_retention"], "24h")
        self.assertEqual(runtime["source"], "default")

    def test_default_runtime_uses_none_reasoning_for_gpt54_models(self) -> None:
        runtime = ai_runtime_config.get_ai_feature_runtime(
            "ai_chat",
            fallback_model="gpt-5.4-nano",
        )

        self.assertEqual(runtime["reasoning"], {"effort": "none"})

    def test_default_runtime_uses_low_reasoning_for_gpt54_mini(self) -> None:
        runtime = ai_runtime_config.get_ai_feature_runtime(
            "ai_chat",
            fallback_model="gpt-5.4-mini",
        )

        self.assertEqual(runtime["reasoning"], {"effort": "low"})

    def test_v3_runtime_is_server_owned_luna_with_low_reasoning(self) -> None:
        with mock.patch.object(
            ai_runtime_config.config,
            "AI_V3_MODEL",
            "gpt-5.6-luna",
        ), mock.patch.object(
            ai_runtime_config.config,
            "AI_V3_REASONING_EFFORT",
            "low",
        ):
            runtime = ai_runtime_config.get_ai_feature_runtime(
                "ai_chat_v3",
                fallback_model="legacy-model",
            )

        self.assertEqual(runtime["feature"], "ai_chat_v3")
        self.assertEqual(runtime["model"], "gpt-5.6-luna")
        self.assertEqual(runtime["reasoning"], {"effort": "low"})
        self.assertEqual(runtime["max_output_tokens"], 8192)
        self.assertEqual(runtime["system_prompt"], "")


if __name__ == "__main__":
    unittest.main()
