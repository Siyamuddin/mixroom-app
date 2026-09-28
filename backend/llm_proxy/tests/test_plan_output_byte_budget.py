"""Backward-compatible V3 serialized-plan byte-budget policy tests."""

import copy
import json
import unittest

from backend.llm_proxy.tests import test_v3_server_contract as helpers
from common import v3_pitch_repair
from common import v3_server_contract as contract


def _plan(commands):
    return {
        "schema_version": contract.PLAN_SCHEMA_VERSION,
        "outcome": "plan",
        "user_message": "Applied the requested changes.",
        "commands": commands,
        "question_options": [],
    }


def _rename_commands(count):
    return [
        {
            "command_id": f"rename-{index}",
            "type": "row.rename",
            "arguments": {"row_id": 101, "new_name": f"Part {index}"},
        }
        for index in range(count)
    ]


def _notes(count):
    return [
        {"pitch": 60, "start_beat": 0, "length_beats": 1, "velocity": 0.8}
        for _ in range(count)
    ]


class PlanOutputByteBudgetTests(unittest.TestCase):
    def context(self, policy=None):
        context = helpers.V3ServerContractTests()._core_context()
        context["project"]["generated_midi_policy"] = contract.GENERATED_MIDI_POLICY
        context["project"]["plan_command_policy"] = contract.PLAN_COMMAND_POLICY
        if policy is not None:
            context["project"]["plan_output_policy"] = policy
        return context

    def surface(self, policy=None):
        return contract.extract_capability_surface(self.context(policy))

    def parse(self, plan, surface, command_types):
        return contract.parse_and_validate_provider_plan(
            v3_pitch_repair.plan_payload(plan),
            command_types=command_types,
            resource_refs_enabled=True,
            capability_surface=surface,
            original_request="Apply these changes.",
        )

    def test_policy_is_opt_in_and_unknown_values_are_conservative(self):
        capable = self.surface(contract.PLAN_OUTPUT_POLICY)
        self.assertEqual(capable.plan_output_policy, contract.PLAN_OUTPUT_POLICY)
        self.assertIsNone(contract.command_limit(capable))
        self.assertIsNone(contract.output_budget(capable).notes)
        self.assertEqual(contract.output_budget(capable).plan_bytes, 64_000)
        self.assertEqual(contract.output_budget(capable).output_tokens, 16_384)

        for policy in (None, "unknown", 64_000, {"bytes": 64_000}):
            surface = self.surface(policy)
            self.assertEqual(surface.plan_output_policy, "")
            self.assertEqual(contract.command_limit(surface), 32)
            self.assertEqual(contract.output_budget(surface).notes, 512)

    def test_more_than_legacy_command_and_note_counts_fit_under_byte_budget(self):
        surface = self.surface(contract.PLAN_OUTPUT_POLICY)
        many_commands = _plan(_rename_commands(33))
        self.assertEqual(
            self.parse(many_commands, surface, ["row.rename"]), many_commands
        )

        many_notes = _plan(
            [
                {
                    "command_id": "notes",
                    "type": "midi.replace_notes",
                    "arguments": {"clip_id": "clip-1", "notes": _notes(513)},
                }
            ]
        )
        self.assertLess(len(contract._canonical_json(many_notes).encode("utf-8")), 64_000)
        self.assertEqual(
            self.parse(many_notes, surface, ["midi.replace_notes"]), many_notes
        )

        legacy = self.surface()
        with self.assertRaises(contract.V3ContractError):
            self.parse(many_commands, legacy, ["row.rename"])
        with self.assertRaises(contract.V3ContractError):
            self.parse(many_notes, legacy, ["midi.replace_notes"])

    def test_policy_removes_only_workload_collection_maxima(self):
        surface = self.surface(contract.PLAN_OUTPUT_POLICY)
        command_types = list(contract.SERVER_COMMAND_TYPES)
        tool = contract.build_submit_plan_tool(
            command_types=command_types,
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        self.assertNotIn("maxItems", tool["parameters"]["properties"]["commands"])

        expected = {
            "group.create": {"members"},
            "clip.glue": {"sources"},
            "midi.create_clip": {"notes"},
            "midi.replace_notes": {"notes"},
            "midi.append_notes": {"notes"},
            "effect.ensure_configured": {"parameters"},
            "automation.set_points": {"points"},
            "sample.place": {"placements"},
        }

        def arrays_named(node, names):
            found = []
            if isinstance(node, dict):
                for name in names:
                    candidate = node.get("properties", {}).get(name)
                    if isinstance(candidate, dict) and candidate.get("type") == "array":
                        found.append(candidate)
                for child in node.values():
                    found.extend(arrays_named(child, names))
            elif isinstance(node, list):
                for child in node:
                    found.extend(arrays_named(child, names))
            return found

        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        for command_type, names in expected.items():
            matching = [
                variant
                for variant in variants
                if contract._command_type_for_variant(variant) == command_type
            ]
            self.assertTrue(matching, command_type)
            arrays = arrays_named(matching, names)
            self.assertTrue(arrays, command_type)
            self.assertTrue(all("maxItems" not in array for array in arrays), command_type)

        serialized = json.dumps(tool, separators=(",", ":"))
        self.assertIn('"maxItems":4', serialized)  # mix intents / clarify options remain bounded.
        self.assertIn('"maxItems":8', serialized)  # mix style tags remain bounded.

    def test_long_midi_clip_is_new_policy_only_and_note_bounds_remain(self):
        command = {
            "command_id": "long-midi",
            "type": "midi.create_clip",
            "arguments": {
                "destination": {"row_id": 101},
                "start_beat": 0,
                "length_beats": 128,
                "notes": [
                    {"pitch": 60, "start_beat": 127, "length_beats": 1, "velocity": 0.8}
                ],
            },
        }
        plan = _plan([command])
        capable = self.surface(contract.PLAN_OUTPUT_POLICY)
        self.assertEqual(self.parse(plan, capable, ["midi.create_clip"]), plan)
        with self.assertRaisesRegex(contract.V3ContractError, "eight-bar"):
            self.parse(plan, self.surface(), ["midi.create_clip"])

        invalid = copy.deepcopy(plan)
        invalid["commands"][0]["arguments"]["notes"][0]["length_beats"] = 2
        with self.assertRaisesRegex(contract.V3ContractError, "extends beyond"):
            self.parse(invalid, capable, ["midi.create_clip"])

    def test_policy_updates_only_new_client_midi_length_guidance(self):
        capable = self.surface(contract.PLAN_OUTPUT_POLICY)
        legacy = self.surface()
        for resource_refs_enabled in (False, True):
            with self.subTest(resource_refs_enabled=resource_refs_enabled):
                capable_instructions = contract._budgeted_instructions(
                    capable, resource_refs_enabled
                )
                legacy_instructions = contract._budgeted_instructions(
                    legacy, resource_refs_enabled
                )
                self.assertNotIn(
                    contract._LEGACY_MIDI_LENGTH_INSTRUCTION,
                    capable_instructions,
                )
                self.assertIn(
                    contract._BYTE_BUDGET_MIDI_LENGTH_INSTRUCTION,
                    capable_instructions,
                )
                self.assertIn(
                    contract._LEGACY_MIDI_LENGTH_INSTRUCTION,
                    legacy_instructions,
                )
                self.assertNotIn(
                    contract._BYTE_BUDGET_MIDI_LENGTH_INSTRUCTION,
                    legacy_instructions,
                )

    def test_plan_byte_ceiling_runs_before_schema_validation(self):
        surface = self.surface(contract.PLAN_OUTPUT_POLICY)
        plan = _plan([])
        plan["padding"] = "x" * 64_000
        with self.assertRaisesRegex(contract.V3ContractError, "output budget"):
            self.parse(plan, surface, ["row.rename"])


if __name__ == "__main__":
    unittest.main()
