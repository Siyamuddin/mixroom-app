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
            "v3_instructions.txt": "e5be3fc19a013ca4a5e5fa3b0e9a55fd7711136530b8e5dac4e9eecea4d5e327",
            "v3_instructions_resource_refs.txt": "2758f7938f575672c7ad09ac7c405793e6e38de83f47ad61541b10cda0cdb506",
            "v3_submit_plan_tool.json": "618f7ae8d98a6c4aa5b8816492f5296dfbac52d943a557aa1669970db6162c42",
            "v3_submit_plan_tool_resource_refs.json": "4598d32a7846cb5caa04557f4a2597aca0febe7a1751649b507add79b638ffd1",
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
            "user_message": "Done.",
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
