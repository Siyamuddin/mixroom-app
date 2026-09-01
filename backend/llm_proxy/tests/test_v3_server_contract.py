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
    def _core_context(self) -> dict:
        return {
            "schema_version": "core_context_v3_prototype_1",
            "project": {
                "row_capacity": {
                    "current_rows": 1,
                    "max_rows": 5,
                    "can_create": True,
                }
            },
            "rows": [
                {
                    "row_id": 101,
                    "lane_kind": "instrument",
                    "instrument_id": "free-piano",
                    "mix_processing_supported": True,
                    "has_usable_signal": True,
                    "effects": [{"effect_instance_id": "fx-1"}],
                }
            ],
            "clips": [
                {
                    "clip_id": "clip-1",
                    "row_id": 101,
                    "kind": "midi",
                    "instrument_id": "free-piano",
                    "length_beats": 8,
                    "midi_notes": [],
                }
            ],
            "groups": [],
            "library_assets": [{"asset_id": "asset-1"}],
            "instruments": ["free-piano"],
            "instrument_catalog": [
                {
                    "instrument_id": "free-piano",
                    "name": "Free Piano",
                    "playable_pitch_ranges": [{"low": 40, "high": 84}],
                }
            ],
            "effects": [
                {
                    "effect_id": "Distortion",
                    "parameters": [
                        {"parameter_id": "Drive", "range": [0, 1]},
                        {"parameter_id": "HPF Frequency", "range": [0.1, 0.9]},
                    ],
                },
                {
                    "effect_id": "Reverb",
                    "parameters": [{"parameter_id": "Mix", "range": [0, 1]}],
                },
                {
                    "effect_id": "EQ 3-Band",
                    "parameters": [
                        {"parameter_id": "Mid Gain", "range": [0, 1]}
                    ],
                },
                {
                    "effect_id": "EQ Parametric",
                    "parameters": [
                        {"parameter_id": "Band 1 Gain", "range": [0, 1]}
                    ],
                },
                {
                    "effect_id": "Compressor",
                    "parameters": [{"parameter_id": "Mix", "range": [0, 1]}],
                },
                {
                    "effect_id": "Limiter",
                    "parameters": [
                        {"parameter_id": "Threshold", "range": [0, 1]}
                    ],
                },
            ],
        }

    def _surface(self):
        return v3_server_contract.extract_capability_surface(self._core_context())

    def _free_context_with_preserved_paid_instrument(self) -> dict:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 2,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = [
            context["rows"][0],
            {
                "row_id": 102,
                "lane_kind": "instrument",
                "instrument_id": "paid-orchestral-strings",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            },
        ]
        context["clips"] = [
            context["clips"][0],
            {
                "clip_id": "clip-paid",
                "row_id": 102,
                "kind": "midi",
                "instrument_id": "paid-orchestral-strings",
                "length_beats": 8,
                "midi_notes": [],
            },
        ]
        return context

    def _free_context_above_creation_limit(self) -> dict:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 6,
            "max_rows": 5,
            "can_create": False,
        }
        context["rows"] = [
            {
                "row_id": row_id,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": True,
                "has_usable_signal": False,
                "effects": [],
            }
            for row_id in range(1, 7)
        ]
        context["clips"] = []
        return context

    def _provider_payload(self, plan: dict) -> dict:
        return {
            "output": [
                {
                    "type": "function_call",
                    "name": "submit_plan_v3",
                    "arguments": json.dumps(plan),
                }
            ]
        }

    def _effect_plan(self, effect_id: str, parameters: list[dict]) -> dict:
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Updated the sound.",
            "commands": [
                {
                    "command_id": "effect-1",
                    "type": "effect.ensure_configured",
                    "arguments": {
                        "row_id": 101,
                        "effect_id": effect_id,
                        "parameters": parameters,
                    },
                }
            ],
            "question_options": [],
        }

    def _transport_restart_plan(self) -> dict:
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Restarted playback.",
            "commands": [
                {
                    "command_id": "restart-1",
                    "type": "transport.restart",
                    "arguments": {},
                }
            ],
            "question_options": [],
        }

    def _mix_plan(self, intent_kind: str) -> dict:
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Adjusted the mix.",
            "commands": [
                {
                    "command_id": "mix-1",
                    "type": "mix.apply_goal",
                    "arguments": {
                        "target": {"scope": "all_rows"},
                        "intents": [
                            {
                                "kind": intent_kind,
                                "direction": "up",
                                "descriptor": None,
                            }
                        ],
                        "intensity": 0.6,
                        "execution_profile": "producer_safe",
                        "audibility": "noticeable",
                        "style_tags": [],
                        "reset_fx": False,
                        "reference": None,
                    },
                }
            ],
            "question_options": [],
        }

    def _surface_with_effects(self, effect_ids: set[str]):
        context = self._core_context()
        context["effects"] = [
            {"effect_id": effect_id, "parameters": []}
            for effect_id in sorted(effect_ids)
        ]
        return v3_server_contract.extract_capability_surface(context)

    def _runtime_mix_intents(self, surface) -> set[str]:
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"mix.apply_goal"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )
        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        mix_variant = next(
            variant
            for variant in variants
            if variant["properties"]["type"]["enum"] == ["mix.apply_goal"]
        )
        return set(
            mix_variant["properties"]["arguments"]["properties"]["intents"]
            ["items"]["properties"]["kind"]["enum"]
        )

    def _runtime_mix_targets(self, surface, *, resource_refs_enabled=False) -> list[dict]:
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"mix.apply_goal"},
            resource_refs_enabled=resource_refs_enabled,
            capability_surface=surface,
        )
        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        mix_variant = next(
            variant
            for variant in variants
            if variant["properties"]["type"]["enum"] == ["mix.apply_goal"]
        )
        return mix_variant["properties"]["arguments"]["properties"]["target"]["anyOf"]

    def _runtime_command_variant(self, tool: dict, command_type: str) -> dict | None:
        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        return next(
            (
                variant
                for variant in variants
                if variant["properties"]["type"]["enum"] == [command_type]
            ),
            None,
        )

    def _readiness_context(self) -> dict:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 4,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = [
            {
                **context["rows"][0],
                "has_usable_signal": False,
            },
            {
                "row_id": 102,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": False,
                "has_usable_signal": False,
                "effects": [],
            },
            {
                "row_id": 103,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": False,
                "has_usable_signal": False,
                "effects": [],
            },
            {
                "row_id": 104,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": False,
                "has_usable_signal": False,
                "effects": [],
            },
        ]
        context["groups"] = [
            {"group_id": "mixed", "member_row_ids": [101, 104]},
            {"group_id": "empty", "member_row_ids": [102, 103]},
        ]
        return context

    def test_approved_v3_contract_assets_match_golden_hashes(self) -> None:
        expected = {
            "v3_contract_metadata.json": "5675e9adbf19cdbbf87cd1229adaf80d5228744202683f9fe391faf47a766fc8",
            "v3_instructions.txt": "fb0a3898a849210cde4c537c2b60e60de563e94d3b37af8da1ee4b4734bda3d1",
            "v3_instructions_resource_refs.txt": "ac804724070fbd8898990be49d6586b003cd543bd4b48da402de6d73242ed79f",
            "v3_submit_plan_tool.json": "4376926c5add3526a1402aa9056d659457be8c479efa2675be743fdcb7c1a301",
            "v3_submit_plan_tool_resource_refs.json": "770858c5722b9aba83826773b4a48b98cf08f4f776718afecc0ce02236ac9775",
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
            capability_surface=request["capability_surface"],
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
                "rows": [
                    {
                        "row_id": row_id,
                        "lane_kind": "audio",
                        "mix_processing_supported": True,
                        "has_usable_signal": False,
                        "effects": [],
                    }
                    for row_id in range(5)
                ],
                "clips": [],
                "groups": [],
                "library_assets": [],
                "instruments": [],
                "instrument_catalog": [],
                "effects": [],
            },
            "supported_command_types": {"row.create"},
            "resource_refs_enabled": False,
        }
        request["capability_surface"] = v3_server_contract.extract_capability_surface(
            request["core_context"]
        )
        provider_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
        )
        self.assertIn(
            "Treat project.row_capacity as authoritative",
            provider_request["instructions"],
        )
        self.assertIn(
            "copy exact effect_id and parameter_id values from core_context.effects",
            provider_request["instructions"],
        )
        self.assertIn(
            "Do not invent control-level settings",
            provider_request["instructions"],
        )
        self.assertIn(
            "combine named effect commands with mix.apply_goal",
            provider_request["instructions"],
        )
        self.assertIn(
            "language of the latest user",
            provider_request["instructions"],
        )
        self.assertEqual(len(provider_request["messages"][0]["content"]), 3)
        self.assertNotIn("RESPONSE_LANGUAGE", json.dumps(provider_request))
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
                capability_surface=self._surface(),
            )
        self.assertEqual(raised.exception.code, "v3_plan_schema_invalid")

    def test_runtime_effect_schema_rejects_hpf_and_wrong_effect_pairing(self) -> None:
        for effect_id, parameter_id in [
            ("Distortion", "hpf"),
            ("Distortion", "Mix"),
            ("Paid Plugin", "Drive"),
        ]:
            with self.subTest(effect_id=effect_id, parameter_id=parameter_id):
                with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                    v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(
                            self._effect_plan(
                                effect_id,
                                [{"parameter_id": parameter_id, "value": 0.5}],
                            )
                        ),
                        command_types={"effect.ensure_configured"},
                        resource_refs_enabled=False,
                        capability_surface=self._surface(),
                    )
                self.assertEqual(raised.exception.code, "v3_plan_schema_invalid")

    def test_runtime_effect_schema_accepts_exact_ids_ranges_and_defaults(self) -> None:
        for parameters in [
            [],
            [{"parameter_id": "HPF Frequency", "value": 0.5}],
        ]:
            plan = self._effect_plan("Distortion", parameters)
            validated = v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"effect.ensure_configured"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
            )
            self.assertEqual(validated, plan)

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(
                    self._effect_plan(
                        "Distortion",
                        [{"parameter_id": "HPF Frequency", "value": 0.05}],
                    )
                ),
                command_types={"effect.ensure_configured"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
            )
        self.assertEqual(raised.exception.code, "v3_plan_schema_invalid")

    def test_semantic_validation_rejects_duplicate_effect_parameters(self) -> None:
        plan = self._effect_plan(
            "Distortion",
            [
                {"parameter_id": "Drive", "value": 0.4},
                {"parameter_id": "Drive", "value": 0.4},
            ],
        )
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"effect.ensure_configured"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
            )
        self.assertEqual(raised.exception.code, "v3_plan_parameter_duplicate")

    def test_capability_surface_rejects_duplicate_and_inconsistent_context(self) -> None:
        duplicate = self._core_context()
        duplicate["effects"].append(duplicate["effects"][0])
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(duplicate)
        self.assertEqual(raised.exception.code, "v3_capability_context_duplicate")

        inconsistent = self._core_context()
        inconsistent["project"]["row_capacity"]["current_rows"] = 2
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(inconsistent)
        self.assertEqual(raised.exception.code, "v3_capability_context_invalid")

    def test_capability_surface_rejects_clip_when_no_rows_exist(self) -> None:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 0,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = []

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(context)

        self.assertEqual(raised.exception.code, "v3_capability_context_invalid")

    def test_capability_surface_rejects_invalid_clip_row_ids(self) -> None:
        for invalid_row_id in (None, True, False, 101.0, "101", -1, [], {}, 999):
            with self.subTest(row_id=invalid_row_id):
                context = self._core_context()
                if isinstance(invalid_row_id, bool):
                    context["rows"][0]["row_id"] = int(invalid_row_id)
                context["clips"][0]["row_id"] = invalid_row_id

                with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                    v3_server_contract.extract_capability_surface(context)

                self.assertEqual(
                    raised.exception.code, "v3_capability_context_invalid"
                )

    def test_runtime_schema_prunes_empty_stable_identifier_alternatives(self) -> None:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 0,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = []
        context["clips"] = []
        context["groups"] = []
        context["library_assets"] = []
        context["instruments"] = []
        context["instrument_catalog"] = []
        context["effects"] = []
        surface = v3_server_contract.extract_capability_surface(context)

        tool = v3_server_contract.build_submit_plan_tool(
            command_types={
                "clip.delete",
                "effect.remove",
                "effect.set_bypassed",
                "group.remove_row",
                "row.create",
                "row.delete",
            },
            resource_refs_enabled=True,
            capability_surface=surface,
        )

        self.assertIsNone(self._runtime_command_variant(tool, "effect.remove"))
        self.assertIsNone(
            self._runtime_command_variant(tool, "effect.set_bypassed")
        )
        clip_delete = json.dumps(
            self._runtime_command_variant(tool, "clip.delete"),
            separators=(",", ":"),
        )
        row_delete = json.dumps(
            self._runtime_command_variant(tool, "row.delete"),
            separators=(",", ":"),
        )
        group_remove = json.dumps(
            self._runtime_command_variant(tool, "group.remove_row"),
            separators=(",", ":"),
        )
        self.assertNotIn('"clip_id"', clip_delete)
        self.assertIn('"clip_ref"', clip_delete)
        self.assertNotIn('"row_id"', row_delete)
        self.assertIn('"row_ref"', row_delete)
        self.assertNotIn('"group_id"', group_remove)
        self.assertIn('"group_ref"', group_remove)

        oversized = self._core_context()
        oversized["effects"][0]["parameters"] = [
            {"parameter_id": f"Parameter {index}", "range": [0, 1]}
            for index in range(v3_server_contract.MAX_EFFECT_PARAMETERS + 1)
        ]
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(oversized)
        self.assertEqual(raised.exception.code, "v3_capability_context_limit")

    def test_free_context_accepts_preserved_paid_instrument_state(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._free_context_with_preserved_paid_instrument()
        )

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(self._transport_restart_plan()),
            command_types={"transport.restart"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )

        self.assertEqual({row.row_id for row in surface.rows}, {101, 102})
        self.assertEqual(surface.current_rows, 2)
        self.assertEqual(validated, self._transport_restart_plan())

    def test_free_context_accepts_rows_above_creation_limit(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._free_context_above_creation_limit()
        )

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(self._transport_restart_plan()),
            command_types={"transport.restart"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )

        self.assertEqual(surface.current_rows, 6)
        self.assertEqual(surface.maximum_rows, 5)
        self.assertEqual(validated, self._transport_restart_plan())

    def test_free_plan_cannot_newly_select_preserved_paid_instrument(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._free_context_with_preserved_paid_instrument()
        )
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Changed the instrument.",
            "commands": [
                {
                    "command_id": "instrument-1",
                    "type": "row.set_instrument",
                    "arguments": {
                        "row_id": 101,
                        "instrument_id": "paid-orchestral-strings",
                    },
                }
            ],
            "question_options": [],
        }

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"row.set_instrument"},
                resource_refs_enabled=False,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_schema_invalid")

    def test_free_plan_cannot_create_row_above_creation_limit(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._free_context_above_creation_limit()
        )
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Created another row.",
            "commands": [
                {
                    "command_id": "row-1",
                    "type": "row.create",
                    "arguments": {
                        "name": "Another row",
                        "lane": {"kind": "audio"},
                        "position": {"kind": "end"},
                    },
                }
            ],
            "question_options": [],
        }

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_row_capacity_exceeded")

    def test_runtime_schema_contains_only_tier_filtered_capabilities(self) -> None:
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"effect.ensure_configured", "row.create"},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
        )
        encoded = json.dumps(tool)
        self.assertIn('"Distortion"', encoded)
        self.assertIn('"free-piano"', encoded)
        self.assertNotIn("Paid Plugin", encoded)
        self.assertNotIn("paid-piano", encoded)
        self.assertLess(
            len(encoded.encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

        reduced_context = self._core_context()
        reduced_context["effects"] = reduced_context["effects"][:1]
        reduced_surface = v3_server_contract.extract_capability_surface(
            reduced_context
        )
        first_fingerprint = v3_server_contract.contract_fingerprint(
            command_types={"effect.ensure_configured"},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
        )
        second_fingerprint = v3_server_contract.contract_fingerprint(
            command_types={"effect.ensure_configured"},
            resource_refs_enabled=False,
            capability_surface=reduced_surface,
        )
        self.assertNotEqual(first_fingerprint, second_fingerprint)

    def test_runtime_mix_schema_excludes_intents_missing_required_effects(self) -> None:
        free_effects = {
            "Reverb",
            "EQ 3-Band",
            "EQ Parametric",
            "Delay",
            "Compressor",
            "Limiter",
        }
        self.assertEqual(
            self._runtime_mix_intents(self._surface_with_effects(free_effects)),
            {
                "balance",
                "compressor",
                "delay",
                "eq",
                "gain",
                "limiter",
                "pan",
                "reverb",
            },
        )

    def test_runtime_mix_schema_keeps_all_intents_for_paid_effect_surface(self) -> None:
        paid_effects = {
            "Reverb",
            "EQ 3-Band",
            "EQ Parametric",
            "Delay",
            "Distortion",
            "De-Esser",
            "Compressor",
            "Limiter",
            "Clipper",
        }
        self.assertEqual(
            self._runtime_mix_intents(self._surface_with_effects(paid_effects)),
            {
                "balance",
                "clipper",
                "compressor",
                "deesser",
                "delay",
                "distortion",
                "eq",
                "gain",
                "limiter",
                "pan",
                "reverb",
            },
        )

    def test_semantic_validation_rejects_mix_intent_outside_effect_surface(self) -> None:
        surface = self._surface_with_effects({"Reverb"})
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                self._mix_plan("distortion"), surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_existing_paid_effect_instance_remains_removable_and_bypassable(self) -> None:
        context = self._core_context()
        context["effects"] = [{"effect_id": "Reverb", "parameters": []}]
        context["rows"][0]["effects"] = [
            {"effect_instance_id": "paid-distortion-1", "effect_id": "Distortion"}
        ]
        surface = v3_server_contract.extract_capability_surface(context)
        for command_type, arguments in (
            ("effect.remove", {"effect_instance_id": "paid-distortion-1"}),
            (
                "effect.set_bypassed",
                {"effect_instance_id": "paid-distortion-1", "bypassed": True},
            ),
        ):
            with self.subTest(command_type=command_type):
                plan = {
                    "schema_version": "plan_v3_prototype_2",
                    "outcome": "plan",
                    "user_message": "Updated the existing effect.",
                    "commands": [
                        {
                            "command_id": "existing-effect",
                            "type": command_type,
                            "arguments": arguments,
                        }
                    ],
                    "question_options": [],
                }
                validated = v3_server_contract.parse_and_validate_provider_plan(
                    self._provider_payload(plan),
                    command_types={command_type},
                    resource_refs_enabled=False,
                    capability_surface=surface,
                )
                self.assertEqual(validated, plan)

    def test_representative_paid_schema_stays_inside_runtime_size_budget(self) -> None:
        paid_effect_ids = [
            "Gain",
            "EQ 3-Band",
            "Compressor",
            "Dynamic Softener",
            "Transient Shaper",
            "Limiter",
            "Clipper",
            "De-Esser",
            "Distortion",
            "Degrade",
            "Delay",
            "Reverb",
            "EQ Parametric",
            "Pitch Shift",
            "Pitch Corrector",
            "Chorus",
            "Vibrato",
        ]
        context = self._core_context()
        context["effects"] = [
            {
                "effect_id": effect_id,
                "parameters": [
                    {"parameter_id": parameter_id, "range": [0, 1]}
                    for parameter_id in (
                        "Threshold",
                        "Attack",
                        "Release",
                        "Mix",
                    )
                ],
            }
            for effect_id in paid_effect_ids
        ]
        paid_tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=v3_server_contract.extract_capability_surface(
                context
            ),
        )
        self.assertLess(
            len(json.dumps(paid_tool, separators=(",", ":")).encode("utf-8")),
            128 * 1024,
        )

        context["effects"] = context["effects"][:9]
        free_tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=v3_server_contract.extract_capability_surface(
                context
            ),
        )
        self.assertLess(
            len(json.dumps(free_tool, separators=(",", ":")).encode("utf-8")),
            96 * 1024,
        )

    def test_semantic_validation_rejects_stale_tiered_identifiers(self) -> None:
        invalid_arguments = [
            ("row.delete", {"row_id": 999}),
            ("clip.delete", {"clip_id": "missing-clip"}),
            ("effect.remove", {"effect_instance_id": "missing-effect"}),
            ("group.set_collapsed", {"group_id": "missing-group", "collapsed": True}),
            (
                "sample.place",
                {
                    "destination": {"row_id": 101},
                    "placements": [{"asset_id": "paid-asset", "start_beat": 0}],
                },
            ),
            (
                "row.create",
                {
                    "name": "Paid instrument",
                    "lane": {"kind": "midi", "instrument_id": "paid-piano"},
                    "position": {"kind": "end"},
                },
            ),
        ]
        for command_type, arguments in invalid_arguments:
            with self.subTest(command_type=command_type):
                plan = {
                    "commands": [
                        {
                            "command_id": "invalid",
                            "type": command_type,
                            "arguments": arguments,
                        }
                    ]
                }
                with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                    v3_server_contract.validate_plan_capabilities(
                        plan, self._surface()
                    )
                self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_semantic_validation_rejects_capacity_and_invalid_resource_refs(self) -> None:
        capacity_plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Created rows.",
            "commands": [
                {
                    "command_id": f"row-{index}",
                    "type": "row.create",
                    "arguments": {
                        "name": f"Row {index}",
                        "lane": {"kind": "audio"},
                        "position": {"kind": "end"},
                    },
                }
                for index in range(5)
            ],
            "question_options": [],
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(capacity_plan),
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
            )
        self.assertEqual(raised.exception.code, "v3_plan_row_capacity_exceeded")

        invalid_ref_plan = self._effect_plan("Distortion", [])
        invalid_ref_plan["commands"][0]["arguments"].pop("row_id")
        invalid_ref_plan["commands"][0]["arguments"]["row_ref"] = {
            "command_id": "missing-producer",
            "output": "row",
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(invalid_ref_plan),
                command_types={"effect.ensure_configured"},
                resource_refs_enabled=True,
                capability_surface=self._surface(),
            )
        self.assertEqual(raised.exception.code, "v3_plan_resource_ref_invalid")

    def test_complete_mixed_plan_survives_backend_contract_unchanged(self) -> None:
        commands = [
            {
                "command_id": "rewrite",
                "type": "midi.replace_notes",
                "arguments": {
                    "clip_id": "clip-1",
                    "notes": [
                        {
                            "pitch": 52,
                            "start_beat": 0,
                            "length_beats": 1,
                            "velocity": 0.8,
                        }
                    ],
                },
            },
            {
                "command_id": "distortion",
                "type": "effect.ensure_configured",
                "arguments": {
                    "row_id": 101,
                    "effect_id": "Distortion",
                    "parameters": [{"parameter_id": "Drive", "value": 0.7}],
                },
            },
            {
                "command_id": "eq",
                "type": "effect.ensure_configured",
                "arguments": {
                    "row_id": 101,
                    "effect_id": "EQ 3-Band",
                    "parameters": [{"parameter_id": "Mid Gain", "value": 0.6}],
                },
            },
            {
                "command_id": "compressor",
                "type": "effect.ensure_configured",
                "arguments": {
                    "row_id": 101,
                    "effect_id": "Compressor",
                    "parameters": [{"parameter_id": "Mix", "value": 0.65}],
                },
            },
            {
                "command_id": "balance",
                "type": "mix.apply_goal",
                "arguments": {
                    "target": {"scope": "all_rows"},
                    "intents": [
                        {"kind": "balance", "direction": None, "descriptor": None}
                    ],
                    "intensity": 0.6,
                    "execution_profile": "producer_safe",
                    "audibility": "noticeable",
                    "style_tags": ["rock"],
                    "reset_fx": False,
                    "reference": None,
                },
            },
        ]
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Built and balanced the guitar part.",
            "commands": commands,
            "question_options": [],
        }
        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={command["type"] for command in commands},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
        )
        self.assertEqual(validated["commands"], commands)
        self.assertEqual(len(validated["commands"]), 5)

    def test_provider_visible_text_is_preserved_without_language_coercion(self) -> None:
        for message in (
            "Voulez-vous modifier la piste ou le mixage ?",
            "¿Quieres cambiar la pista o la mezcla?",
            "Möchten Sie die Spur oder den Mix ändern?",
            "هل تريد تغيير المسار أم المزج؟",
            "आप ट्रैक बदलना चाहते हैं या मिक्स?",
        ):
            with self.subTest(message=message):
                plan = self._effect_plan("Distortion", [])
                plan["user_message"] = message
                validated = v3_server_contract.parse_and_validate_provider_plan(
                    self._provider_payload(plan),
                    command_types={"effect.ensure_configured"},
                    resource_refs_enabled=False,
                    capability_surface=self._surface(),
                )
                self.assertEqual(validated["commands"], plan["commands"])
                self.assertEqual(validated["user_message"], message)

        clarification = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "clarify",
            "user_message": "Quelle piste voulez-vous modifier ?",
            "commands": [],
            "question_options": ["La guitare", "La basse"],
        }
        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(clarification),
            command_types={"effect.ensure_configured"},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
        )
        self.assertEqual(validated["user_message"], clarification["user_message"])
        self.assertEqual(
            validated["question_options"], clarification["question_options"]
        )

    def test_provider_output_failures_have_safe_distinct_subtypes(self) -> None:
        cases = {
            "v3_provider_output_missing": {},
            "v3_provider_output_refusal": {"output": [{"type": "refusal"}]},
            "v3_provider_tool_call_missing": {"output": []},
            "v3_provider_arguments_invalid_json": {
                "output": [
                    {
                        "type": "function_call",
                        "name": "submit_plan_v3",
                        "arguments": "{",
                    }
                ]
            },
            "v3_provider_output_truncated": {
                "status": "incomplete",
                "incomplete_details": {"reason": "max_output_tokens"},
                "output": [],
            },
        }
        for expected, payload in cases.items():
            with self.subTest(expected=expected):
                with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                    v3_server_contract.parse_and_validate_provider_plan(
                        payload,
                        command_types={"effect.ensure_configured"},
                        resource_refs_enabled=False,
                        capability_surface=self._surface(),
                    )
                self.assertEqual(raised.exception.code, expected)

    def test_output_token_budget_is_bounded(self) -> None:
        request = {
            "original_request": "Warm the mix.",
            "prompt_trace_id": "",
            "resource_refs_enabled": False,
            "supported_command_types": {"effect.ensure_configured"},
            "capability_surface": self._surface(),
            "conversation": [],
            "core_context": self._core_context(),
        }
        provider_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
            max_output_tokens=8000,
        )
        self.assertEqual(provider_request["max_output_tokens"], 8000)
        capped_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
            max_output_tokens=9000,
        )
        self.assertEqual(capped_request["max_output_tokens"], 8192)

    def test_shared_state_contract_fixtures(self) -> None:
        fixture_path = (
            ROOT.parents[1] / "test" / "fixtures" / "ai_v3_state_contract_cases.json"
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        surface = v3_server_contract.extract_capability_surface(fixture["context"])

        for case in fixture["cases"]:
            with self.subTest(case=case["id"]):
                plan = {"commands": case["commands"]}
                if case["accepted"]:
                    final_state = v3_server_contract.validate_plan_capabilities(
                        plan, surface
                    )
                    self.assertEqual(
                        final_state["rows"]["2"]["instrument_id"],
                        case["final_instrument_id"],
                    )
                    self.assertEqual(
                        final_state["clips"]["midi-clip"]["instrument_id"],
                        case["final_instrument_id"],
                    )
                else:
                    with self.assertRaises(
                        v3_server_contract.V3ContractError
                    ) as raised:
                        v3_server_contract.validate_plan_capabilities(plan, surface)
                    self.assertEqual(raised.exception.code, case["backend_error"])

    def test_runtime_schema_excludes_wrong_typed_targets(self) -> None:
        fixture_path = (
            ROOT.parents[1] / "test" / "fixtures" / "ai_v3_state_contract_cases.json"
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        surface = v3_server_contract.extract_capability_surface(fixture["context"])
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"row.set_instrument", "midi.replace_notes"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )
        variants = tool["parameters"]["properties"]["commands"]["items"]["anyOf"]
        encoded_by_type = {
            variant["properties"]["type"]["enum"][0]: json.dumps(variant)
            for variant in variants
        }
        self.assertIn('"enum": [2]', encoded_by_type["row.set_instrument"])
        self.assertNotIn('"enum": [1, 2]', encoded_by_type["row.set_instrument"])
        self.assertIn(
            '"enum": ["midi-clip"]', encoded_by_type["midi.replace_notes"]
        )
        self.assertNotIn("audio-clip", encoded_by_type["midi.replace_notes"])

    def test_runtime_mix_targets_include_only_ready_stable_rows_and_groups(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._readiness_context()
        )
        targets = self._runtime_mix_targets(surface)
        direct_row = next(
            target for target in targets if "row_id" in target.get("properties", {})
        )
        direct_group = next(
            target for target in targets if "group_id" in target.get("properties", {})
        )

        self.assertEqual(direct_row["properties"]["row_id"]["enum"], [101])
        self.assertEqual(
            direct_group["properties"]["group_id"]["enum"], ["mixed"]
        )

    def test_semantic_mix_readiness_rejects_unready_direct_targets(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._readiness_context()
        )
        for target in (
            {"scope": "row", "row_id": 102},
            {"scope": "group", "group_id": "empty"},
        ):
            with self.subTest(target=target):
                plan = self._mix_plan("reverb")
                plan["commands"][0]["arguments"]["target"] = target
                with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                    v3_server_contract.validate_plan_capabilities(plan, surface)
                self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_midi_mix_readiness_does_not_require_analyzed_signal(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._readiness_context()
        )
        plan = self._mix_plan("reverb")
        plan["commands"][0]["arguments"]["target"] = {
            "scope": "row",
            "row_id": 101,
        }

        validated = v3_server_contract.validate_plan_capabilities(plan, surface)

        self.assertEqual(validated["rows"]["101"]["instrument_id"], "free-piano")

    def test_ordered_generated_row_must_be_populated_before_mixing(self) -> None:
        surface = self._surface()
        row_ref = {"command_id": "created", "output": "row"}
        create = {
            "command_id": "created",
            "type": "row.create",
            "arguments": {},
        }
        mix = self._mix_plan("reverb")["commands"][0]
        mix["arguments"]["target"] = {"scope": "row", "row_ref": row_ref}

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [create, mix]}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

        place = {
            "command_id": "place",
            "type": "sample.place",
            "arguments": {
                "destination": {"row_ref": row_ref},
                "placements": [{"asset_id": "asset-1", "start_beat": 0}],
            },
        }
        validated = v3_server_contract.validate_plan_capabilities(
            {"commands": [create, place, mix]}, surface
        )
        self.assertEqual(validated["row_count"], 2)

    def test_deleting_last_clip_makes_later_mix_unavailable(self) -> None:
        surface = self._surface()
        delete = {
            "command_id": "delete",
            "type": "clip.delete",
            "arguments": {"clip_id": "clip-1"},
        }
        mix = self._mix_plan("reverb")["commands"][0]

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [delete, mix]}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_deleting_populated_generated_row_removes_later_mix_readiness(self) -> None:
        context = self._readiness_context()
        for row in context["rows"]:
            row["mix_processing_supported"] = False
        surface = v3_server_contract.extract_capability_surface(context)
        row_ref = {"command_id": "created", "output": "row"}
        commands = [
            {
                "command_id": "created",
                "type": "row.create",
                "arguments": {},
            },
            {
                "command_id": "place",
                "type": "sample.place",
                "arguments": {
                    "destination": {"row_ref": row_ref},
                    "placements": [{"asset_id": "asset-1", "start_beat": 0}],
                },
            },
            {
                "command_id": "delete-row",
                "type": "row.delete",
                "arguments": {"row_ref": row_ref},
            },
            self._mix_plan("reverb")["commands"][0],
        ]
        commands[-1]["arguments"]["target"] = {"scope": "master"}

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": commands}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_duplicate_makes_empty_destination_row_mixable(self) -> None:
        context = self._readiness_context()
        context["rows"][1]["lane_kind"] = "instrument"
        context["rows"][1]["instrument_id"] = "free-piano"
        surface = v3_server_contract.extract_capability_surface(context)
        duplicate = {
            "command_id": "duplicate",
            "type": "clip.duplicate_to",
            "arguments": {
                "clip_id": "clip-1",
                "destination_row_id": 102,
                "start_beat": 8,
            },
        }
        mix = self._mix_plan("reverb")["commands"][0]
        mix["arguments"]["target"] = {"scope": "row", "row_id": 102}

        validated = v3_server_contract.validate_plan_capabilities(
            {"commands": [duplicate, mix]}, surface
        )
        self.assertEqual(validated["row_count"], 4)

    def test_deleting_both_split_outputs_removes_source_row_readiness(self) -> None:
        surface = self._surface()
        split = {
            "command_id": "split",
            "type": "clip.split_at",
            "arguments": {"clip_id": "clip-1", "at_beat": 4},
        }
        delete_left = {
            "command_id": "delete-left",
            "type": "clip.delete",
            "arguments": {
                "clip_ref": {"command_id": "split", "output": "left_clip"}
            },
        }
        delete_right = {
            "command_id": "delete-right",
            "type": "clip.delete",
            "arguments": {
                "clip_ref": {"command_id": "split", "output": "right_clip"}
            },
        }
        mix = self._mix_plan("reverb")["commands"][0]

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [split, delete_left, delete_right, mix]}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_deleting_glued_output_removes_consumed_row_readiness(self) -> None:
        context = self._core_context()
        context["rows"][0].update(
            {"lane_kind": "audio", "instrument_id": ""}
        )
        context["clips"] = [
            {"clip_id": "audio-a", "row_id": 101, "kind": "audio"},
            {"clip_id": "audio-b", "row_id": 101, "kind": "audio"},
        ]
        surface = v3_server_contract.extract_capability_surface(context)
        glue = {
            "command_id": "glue",
            "type": "clip.glue",
            "arguments": {
                "sources": [{"clip_id": "audio-a"}, {"clip_id": "audio-b"}]
            },
        }
        delete = {
            "command_id": "delete-glue",
            "type": "clip.delete",
            "arguments": {
                "clip_ref": {"command_id": "glue", "output": "glued_clip"}
            },
        }
        mix = self._mix_plan("reverb")["commands"][0]

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [glue, delete, mix]}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")


if __name__ == "__main__":
    unittest.main()
