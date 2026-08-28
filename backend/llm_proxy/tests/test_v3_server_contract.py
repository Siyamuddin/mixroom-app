from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import v3_server_contract  # noqa: E402


class V3ServerContractTests(unittest.TestCase):
    def test_approved_v3_contract_assets_match_golden_hashes(self) -> None:
        expected = {
            "v3_align_tempo_retry_instructions.txt": "84c3f2fd94c9d57fb43a898d6b9748b026723d1d4503506ddfd7597b7d5926af",
            "v3_contract_metadata.json": "5675e9adbf19cdbbf87cd1229adaf80d5228744202683f9fe391faf47a766fc8",
            "v3_instructions.txt": "ad510332fce4e664170d5ab5378f6af41e16cbbda17128de0e85c0f96643f94e",
            "v3_instructions_resource_refs.txt": "9970f056882aa24ea58aab1c9a9dee2205d6c64c04e9d0ffc8de37def76ac96b",
            "v3_submit_plan_tool.json": "c6e02a820f22501a5b98af38f57ab8ff32b4ab65a31c8766adf60eab2cbdeb4c",
            "v3_submit_plan_tool_resource_refs.json": "d526ff016dbd0a18abc34821e43c8251af9f3eda14239d583775e5fe8f8b33c2",
        }
        asset_directory = SRC / "common" / "v3_contract_assets"
        actual = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in asset_directory.iterdir()
            if path.is_file()
        }
        self.assertEqual(actual, expected)

    def test_capability_intersection_cannot_expand_server_surface(self) -> None:
        request = v3_server_contract.validate_context_request(
            {
                "request_contract": "mixroom_v3_context_v1",
                "original_request": "Restart.",
                "conversation": [],
                "core_context": {"schema_version": "core_context_v3_prototype_1"},
                "plan_schema_version": "plan_v3_prototype_2",
                "supported_command_types": [
                    "transport.restart",
                    "attacker.execute_arbitrary_code",
                ],
                "resource_refs_enabled": False,
            },
            raw_body_bytes=500,
        )
        self.assertEqual(request["supported_command_types"], {"transport.restart"})
        tool = v3_server_contract.build_submit_plan_tool(
            command_types=request["supported_command_types"],
            resource_refs_enabled=False,
        )
        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        self.assertEqual(
            [variant["properties"]["type"]["enum"][0] for variant in variants],
            ["transport.restart"],
        )

    def test_row_capacity_policy_is_server_owned(self) -> None:
        request = {
            "original_request": "Add a piano row.",
            "conversation": [],
            "core_context": {
                "schema_version": "core_context_v3_prototype_1",
                "project": {
                    "row_capacity": {
                        "current_rows": 5,
                        "max_rows": 5,
                        "can_create": False,
                    }
                },
            },
            "supported_command_types": {"row.create"},
            "resource_refs_enabled": False,
        }
        provider_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
        )
        self.assertIn(
            "Treat project.row_capacity as authoritative",
            provider_request["instructions"],
        )
        self.assertNotIn(
            "row_creation_policy",
            provider_request["messages"][0]["content"][2]["text"],
        )

    def test_provider_schema_rejects_unknown_plan_fields(self) -> None:
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "respond",
            "goal_kind": "question",
            "user_message": "Done.",
            "skipped": [],
            "commands": [],
            "question_options": [],
            "internal_reasoning": "secret",
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                {
                    "output": [
                        {
                            "type": "function_call",
                            "name": "submit_plan_v3",
                            "arguments": json.dumps(plan),
                        }
                    ]
                },
                command_types={"transport.restart"},
                resource_refs_enabled=False,
            )
        self.assertEqual(raised.exception.code, "v3_plan_schema_invalid")

    def test_compound_align_tempo_retry_is_data_driven(self) -> None:
        base = {
            "outcome": "plan",
            "goal_kind": "production_goal",
            "commands": [
                {"type": "clip.align_tempo_to_project"},
                {"type": "clip.align_tempo_to_project"},
            ],
        }
        self.assertTrue(v3_server_contract.should_retry_align_tempo_collapse(base))
        self.assertFalse(
            v3_server_contract.should_retry_align_tempo_collapse(
                {**base, "goal_kind": "named_edit"}
            )
        )
        self.assertFalse(
            v3_server_contract.should_retry_align_tempo_collapse(
                {
                    **base,
                    "commands": [
                        {"type": "clip.align_tempo_to_project"},
                        {"type": "mix.apply_goal"},
                    ],
                }
            )
        )

    def test_compound_retry_request_keeps_server_contract_and_adds_reminder(self) -> None:
        request = {
            "original_request": "Make this a faster, brighter remix.",
            "conversation": [],
            "core_context": {"schema_version": "core_context_v3_prototype_1"},
            "supported_command_types": {
                "clip.align_tempo_to_project",
                "project.set_tempo",
                "mix.apply_goal",
            },
            "resource_refs_enabled": False,
            "prompt_trace_id": "retry-test",
        }
        retried = v3_server_contract.build_align_tempo_retry_provider_request(
            request,
            model="gpt-5.6-luna",
            reasoning_effort="low",
        )
        self.assertIn("previous plan collapsed a production_goal", retried["instructions"])
        self.assertEqual(
            retried["metadata"]["retry_reason"],
            "production_goal_align_tempo_collapse",
        )
        self.assertEqual(retried["tool_choice"]["name"], "submit_plan_v3")
        self.assertFalse(retried["parallel_tool_calls"])


if __name__ == "__main__":
    unittest.main()
