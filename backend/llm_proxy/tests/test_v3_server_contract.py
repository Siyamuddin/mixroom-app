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
            "v3_contract_metadata.json": "5675e9adbf19cdbbf87cd1229adaf80d5228744202683f9fe391faf47a766fc8",
            "v3_instructions.txt": "cf6455c7a0d03670c0f81f3806afa36d61702d10fec3ad9c75ff9cbfda783796",
            "v3_instructions_resource_refs.txt": "c2912bb6a8b4ae571460fecad578ab6ecc24b5f3243c4b64a5b5ab24f3c88f0c",
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


if __name__ == "__main__":
    unittest.main()
