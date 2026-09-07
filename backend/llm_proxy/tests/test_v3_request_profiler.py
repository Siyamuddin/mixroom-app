from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROFILER_PATH = ROOT / "tool" / "ai_v3_eval" / "profile_v3_requests.py"
SPEC = importlib.util.spec_from_file_location("profile_v3_requests", PROFILER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load the V3 request profiler.")
profile_v3_requests = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = profile_v3_requests
SPEC.loader.exec_module(profile_v3_requests)


class V3RequestProfilerTests(unittest.TestCase):
    def test_profiles_are_deterministic_and_match_the_approved_baseline(self) -> None:
        first = profile_v3_requests.run_profiles(iterations=1)
        second = profile_v3_requests.run_profiles(iterations=1)

        first_deterministic = [
            profile_v3_requests.deterministic_profile(profile)
            for profile in first["profiles"]
        ]
        second_deterministic = [
            profile_v3_requests.deterministic_profile(profile)
            for profile in second["profiles"]
        ]
        self.assertEqual(first_deterministic, second_deterministic)
        profile_v3_requests.verify_baseline(first)
        self.assertEqual(
            first["summary"]["largest_boundary_component"],
            "tool_schema",
        )
        self.assertEqual(
            first["summary"]["slowest_local_non_provider_phase"],
            "provider_request_build",
        )
        profiles = {profile["name"]: profile for profile in first["profiles"]}
        for profile in profiles.values():
            self.assertEqual(
                profile["canonical_upstream_request_bytes"],
                profile["provider_request_bytes"] - 3,
            )
            self.assertGreater(
                profile["wire_request_bytes"],
                profile["canonical_upstream_request_bytes"],
            )

        medium = profiles["medium"]
        product_max = profiles["product_max"]
        boundary = profiles["boundary"]
        self.assertGreater(
            medium["tool_schema_bytes"],
            medium["provider_request_bytes"] * 0.85,
        )
        self.assertLess(
            medium["schema_attribution"][
                "resource_identifier_enum_value_bytes"
            ],
            medium["tool_schema_bytes"] * 0.10,
        )
        self.assertGreater(
            boundary["schema_attribution"][
                "resource_identifier_enum_value_bytes"
            ],
            boundary["tool_schema_bytes"] * 0.65,
        )
        self.assertEqual(product_max["row_count"], 32)
        self.assertEqual(product_max["clip_count"], 128)
        self.assertEqual(product_max["midi_note_count"], 512)
        self.assertEqual(product_max["library_asset_count"], 250)
        self.assertEqual(product_max["conversation_turn_count"], 8)
        self.assertEqual(product_max["effective_command_type_count"], 54)
        self.assertEqual(product_max["tool_command_variant_count"], 54)
        self.assertTrue(
            profile_v3_requests.scenarios()["product_max"]["resource_refs_enabled"]
        )

    def test_boundary_profile_is_the_largest_current_valid_context(self) -> None:
        body = profile_v3_requests._boundary_request()
        profile = profile_v3_requests.profile_scenario(
            "boundary",
            body,
            iterations=1,
        )
        self.assertLessEqual(
            profile["core_context_bytes"],
            profile_v3_requests.v3_server_contract.MAX_CORE_CONTEXT_BYTES,
        )

        next_row_count = profile["row_count"] + 1
        next_body = profile_v3_requests._request(
            row_count=next_row_count,
            clip_count=min(
                next_row_count * 4,
                profile_v3_requests.v3_server_contract.MAX_COLLECTION_ITEMS,
            ),
            turn_count=(
                profile_v3_requests.v3_server_contract.MAX_CONVERSATION_TURNS
            ),
            full_command_surface=True,
            padded_conversation=True,
        )
        with self.assertRaises(
            profile_v3_requests.v3_server_contract.V3ContractError
        ) as raised:
            profile_v3_requests._build_provider_request(next_body)
        self.assertIn(
            raised.exception.code,
            {"v3_capability_context_limit", "v3_context_request_limit"},
        )


if __name__ == "__main__":
    unittest.main()
