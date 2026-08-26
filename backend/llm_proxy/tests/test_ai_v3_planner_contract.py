from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common.ai_v3_planner_contract import (  # noqa: E402
    AI_V3_ALIGN_TEMPO_COLLAPSE_RETRY_REMINDER,
    AI_V3_MUSICAL_DIMENSION_COMPILER_INSTRUCTIONS,
    apply_v3_server_owned_instructions,
    build_v3_planner_instructions,
)


class AiV3PlannerContractTests(unittest.TestCase):
    def test_stable_prompt_includes_planner_and_compiler(self) -> None:
        prompt = build_v3_planner_instructions()
        self.assertIn("You are Mixroom's sole semantic and musical planner.", prompt)
        self.assertIn(AI_V3_MUSICAL_DIMENSION_COMPILER_INSTRUCTIONS.strip(), prompt)
        self.assertIn("Set goal_kind from ORIGINAL_REQUEST_VERBATIM only", prompt)
        self.assertNotIn("Recognized style", prompt)
        self.assertNotIn(
            AI_V3_ALIGN_TEMPO_COLLAPSE_RETRY_REMINDER.strip(),
            prompt,
        )
        self.assertNotIn(
            "A later command may target a documented typed output",
            prompt,
        )

    def test_request_local_flags_append_owned_extras(self) -> None:
        prompt = build_v3_planner_instructions(
            resource_refs_enabled=True,
            align_tempo_collapse_retry=True,
        )
        self.assertIn(AI_V3_ALIGN_TEMPO_COLLAPSE_RETRY_REMINDER.strip(), prompt)
        self.assertIn(
            "A later command may target a documented typed output",
            prompt,
        )

    def test_client_instructions_are_replaced(self) -> None:
        request_body = {
            "instructions": "client-owned V3 planner instructions",
            "metadata": {
                "architecture": "v3_one_shot_prototype",
                "v3_align_tempo_retry": "1",
                "v3_resource_refs": "1",
            },
        }
        apply_v3_server_owned_instructions(request_body)
        self.assertNotIn("client-owned", request_body["instructions"])
        self.assertIn(
            AI_V3_MUSICAL_DIMENSION_COMPILER_INSTRUCTIONS.strip(),
            request_body["instructions"],
        )
        self.assertIn(
            AI_V3_ALIGN_TEMPO_COLLAPSE_RETRY_REMINDER.strip(),
            request_body["instructions"],
        )
        self.assertIn(
            "A later command may target a documented typed output",
            request_body["instructions"],
        )

    def test_missing_client_instructions_still_receive_server_prompt(self) -> None:
        request_body: dict[str, object] = {"input": []}
        apply_v3_server_owned_instructions(request_body)
        self.assertIn(
            "You are Mixroom's sole semantic and musical planner.",
            str(request_body["instructions"]),
        )


if __name__ == "__main__":
    unittest.main()
