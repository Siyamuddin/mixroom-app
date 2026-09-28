from __future__ import annotations

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
PRIVATE_CONTEXT_ESCAPE_FIXTURE = (
    Path(__file__).with_name("fixtures")
    / "v3_private_context_message_escape.json"
)
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from common import v3_server_contract  # noqa: E402


class V3ServerContractTests(unittest.TestCase):
    def test_provider_wire_budget_is_derived_from_validated_context_budget(self) -> None:
        self.assertEqual(
            v3_server_contract.MAX_PROVIDER_WIRE_BYTES,
            (
                v3_server_contract.DYNAMIC_MAX_CORE_CONTEXT_BYTES
                * v3_server_contract.MAX_PROVIDER_CORE_TRANSFORM_MULTIPLIER
                * v3_server_contract.MAX_PROVIDER_JSON_ESCAPE_MULTIPLIER
                + v3_server_contract.MAX_PROVIDER_NON_CORE_WIRE_BYTES
            ),
        )

    def test_provider_context_annotation_stays_below_transform_ceiling(self) -> None:
        # This deliberately omits fields required by a valid clip, making each
        # source object smaller and the measured expansion more conservative.
        context = {
            "clips": [
                {"kind": "midi", "length_beats": 0, "start_beat": 0}
                for _ in range(1_000)
            ]
        }
        source_bytes = len(
            v3_server_contract._canonical_json(context).encode("utf-8")
        )
        provider_bytes = len(
            v3_server_contract._canonical_json(
                v3_server_contract._provider_core_context(context)
            ).encode("utf-8")
        )

        self.assertLessEqual(
            provider_bytes,
            source_bytes
            * v3_server_contract.MAX_PROVIDER_CORE_TRANSFORM_MULTIPLIER,
        )

    def test_existing_notes_use_context_budget_not_output_budget(self):
        for count in (300, 512, 513, 600, 1024):
            context = self._core_context()
            notes = [{"pitch": 60, "start_beat": 0, "length_beats": 1,
                      "velocity": 0.8} for _ in range(count)]
            context["clips"][0]["midi_notes"] = notes
            body = {
                "request_contract": "mixroom_v3_context_v2",
                "original_request": "Rebalance without changing notes.",
                "conversation": [], "core_context": context,
                "plan_schema_version": "plan_v3_prototype_2",
                "supported_command_types": ["transport.restart"],
                "resource_refs_enabled": False,
            }
            validated = v3_server_contract.validate_context_request(
                body, raw_body_bytes=len(json.dumps(body).encode()))
            self.assertEqual(validated["core_context"]["clips"][0]["midi_notes"], notes)
            self.assertEqual(len(validated["capability_surface"].clips[0].midi_notes), count)
            self.assertEqual(v3_server_contract.output_budget(validated["capability_surface"]).notes, 256)
            self.assertEqual(v3_server_contract.command_limit(validated["capability_surface"]), 16)

        # The exemption is path-specific, not based on an arbitrary key name.
        for context in ({"midi_notes": notes}, {"other": {"midi_notes": notes}}):
            with self.assertRaises(v3_server_contract.V3ContractError):
                v3_server_contract._validate_context_value(context)

        # Notes beyond the former ceiling still undergo normal validation.
        notes[-1]["pitch"] = 128
        with self.assertRaises(v3_server_contract.V3ContractError) as caught:
            v3_server_contract.validate_context_request(body, raw_body_bytes=100000)
        self.assertEqual(caught.exception.code, "v3_capability_context_invalid")
        notes[-1]["pitch"] = 60

        body["core_context"]["padding"] = ["x" * 30000] * 3
        with self.assertRaises(v3_server_contract.V3ContractError) as caught:
            v3_server_contract.validate_context_request(body, raw_body_bytes=170000)
        self.assertEqual(caught.exception.code, "v3_context_request_limit")
        with self.assertRaises(v3_server_contract.V3ContractError):
            v3_server_contract.validate_context_request(body, raw_body_bytes=180001)

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

    def test_capability_repair_details_use_only_bounded_categories(self) -> None:
        expected_kinds = {
            "cannot_delete_row",
            "incompatible_glue_sources",
            "invalid_effect_parameter_value",
            "invalid_group_membership",
            "missing_effective_instrument",
            "unavailable_asset",
            "unavailable_clip",
            "unavailable_effect",
            "unavailable_effect_instance",
            "unavailable_effect_parameter",
            "unavailable_group",
            "unavailable_group_membership",
            "unavailable_instrument",
            "unavailable_mix_intent",
            "unavailable_row",
            "unmixable_target",
        }
        self.assertEqual(
            v3_server_contract._CAPABILITY_FAILURE_KINDS, expected_kinds
        )
        for failure_kind in expected_kinds:
            with self.subTest(failure_kind=failure_kind):
                error = v3_server_contract._capability_error(
                    failure_kind,
                    "PRIVATE_RESOURCE_MARKER",
                    command_index=7,
                    command_type="row.rename",
                    field="row_id",
                )
                self.assertEqual(error.code, "v3_plan_capability_invalid")
                self.assertEqual(
                    error.repair_details,
                    {
                        "failure_kind": failure_kind,
                        "command_index": 7,
                        "command_type": "row.rename",
                        "field": "row_id",
                    },
                )
                self.assertNotIn(
                    "PRIVATE_RESOURCE_MARKER",
                    json.dumps(error.repair_details, sort_keys=True),
                )

    def test_capability_validation_attaches_command_context(self) -> None:
        plan = {
            "commands": [
                {
                    "command_id": "restart",
                    "type": "transport.restart",
                    "arguments": {},
                },
                {
                    "command_id": "rename",
                    "type": "row.rename",
                    "arguments": {"row_id": 999, "new_name": "Vocal Space"},
                },
            ]
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(plan, self._surface())
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")
        self.assertEqual(
            raised.exception.repair_details,
            {
                "failure_kind": "unavailable_row",
                "command_index": 1,
                "command_type": "row.rename",
                "field": "row_id",
            },
        )

    def _dynamic_context(self, *, row_count: int = 1, free: bool = False) -> dict:
        context = self._core_context()
        context["project"]["project_capacity_policy"] = (
            v3_server_contract.PROJECT_CAPACITY_POLICY
        )
        context["project"]["row_capacity"] = {
            "current_rows": row_count,
            "creation_limit": 5 if free else None,
            "can_create": row_count < 5 if free else True,
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
            for row_id in range(1, row_count + 1)
        ]
        context["clips"] = []
        context["groups"] = []
        context["instruments"] = []
        context["instrument_catalog"] = []
        return context

    def _group_surface(
        self,
        *,
        members: list[int] | None = None,
        ready_rows: set[int] | None = None,
    ):
        context = self._core_context()
        ready_rows = ready_rows if ready_rows is not None else {1, 2, 3, 4}
        context["project"]["row_capacity"] = {
            "current_rows": 4,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = [
            {
                "row_id": row_id,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": row_id in ready_rows,
                "has_usable_signal": row_id in ready_rows,
                "effects": [],
            }
            for row_id in range(1, 5)
        ]
        context["clips"] = []
        context["groups"] = (
            []
            if members is None
            else [{"group_id": "group-1", "member_row_ids": members}]
        )
        return v3_server_contract.extract_capability_surface(context)

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

    def _phone_cleanup_context(self) -> dict:
        context = self._core_context()
        context["project"]["row_capacity"] = {
            "current_rows": 4,
            "max_rows": 5,
            "can_create": True,
        }
        context["rows"] = [
            {
                "row_id": 101,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [
                    {
                        "effect_instance_id": "cleanup-row-effect",
                        "effect_id": "Reverb",
                    }
                ],
            },
            {
                "row_id": 102,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            },
            {
                "row_id": 103,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            },
            {
                "row_id": 104,
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            },
        ]
        context["clips"] = [
            {
                "clip_id": "audio-101",
                "row_id": 101,
                "kind": "audio",
                "length_beats": 8,
            },
            {
                "clip_id": "audio-102",
                "row_id": 102,
                "kind": "audio",
                "length_beats": 8,
            },
            {
                "clip_id": "audio-103",
                "row_id": 103,
                "kind": "audio",
                "length_beats": 8,
            },
            {
                "clip_id": "audio-104",
                "row_id": 104,
                "kind": "audio",
                "length_beats": 8,
            },
        ]
        context["groups"] = [
            {"group_id": "cleanup-row", "member_row_ids": [101, 102]},
            {"group_id": "other-row", "member_row_ids": [103, 104]},
        ]
        context["instruments"] = []
        context["instrument_catalog"] = []
        return context

    def _phone_cleanup_plan(self, second_command: dict | None = None) -> dict:
        commands = [
            {
                "command_id": "cleanup-1",
                "type": "row.apply_phone_mic_cleanup",
                "arguments": {"row_id": 101},
            }
        ]
        if second_command is not None:
            commands.append(second_command)
        return {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Cleaned up the recording.",
            "commands": commands,
            "question_options": [],
        }

    def _mix_command(self, target: dict, *, command_id: str = "mix-1") -> dict:
        command = self._mix_plan("reverb")["commands"][0]
        return {
            **command,
            "command_id": command_id,
            "arguments": {**command["arguments"], "target": target},
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
            "v3_instructions.txt": "db92912a052c1060ce668a55e4811948080cbf34071454b9cc05ba941be54dba",
            "v3_instructions_resource_refs.txt": "ee2297a73120c0bef602fd97245b3aaeed51645db461851f2b63383ba5edb792",
            "v3_submit_plan_tool.json": "0bde04be9e806437c24675e2e046294d005b5b667f5357757a47feccf59d25cf",
            "v3_submit_plan_tool_resource_refs.json": "ae7ba968bce155b798c3f4465cdab1132abcef4408bf3d2b5a846e0b2c945068",
        }
        asset_directory = SRC / "common" / "v3_contract_assets"
        actual = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in asset_directory.iterdir()
            if path.is_file()
        }
        self.assertEqual(actual, expected)

    def test_playable_note_validation_preserves_range_edges_and_gaps(self) -> None:
        instrument = v3_server_contract.V3InstrumentCapability(
            "synthetic-instrument",
            (
                v3_server_contract.V3MidiPitchRange(40, 60),
                v3_server_contract.V3MidiPitchRange(70, 84),
            ),
        )
        for pitch in (39, 40, 60, 61, 69, 70, 84, 85):
            with self.subTest(pitch=pitch):
                notes = [v3_server_contract.V3MidiNote(pitch, 0.0, 1.0, 0.8)]
                if pitch in (40, 60, 70, 84):
                    v3_server_contract._validate_playable_notes(
                        notes, instrument.instrument_id, {instrument.instrument_id: instrument}
                    )
                else:
                    with self.assertRaises(v3_server_contract.V3ContractError) as caught:
                        v3_server_contract._validate_playable_notes(
                            notes, instrument.instrument_id, {instrument.instrument_id: instrument}
                        )
                    self.assertEqual(caught.exception.code, "v3_plan_midi_pitch_unavailable")

    def test_capability_intersection_cannot_expand_server_surface(self) -> None:
        request = v3_server_contract.validate_context_request(
            {
                "request_contract": "mixroom_v3_context_v2",
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
            "Plan commands against the evolving project state",
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
            "only authority for response language",
            provider_request["instructions"],
        )
        provider_content = provider_request["messages"][0]["content"]
        self.assertEqual(len(provider_content), 3)
        self.assertTrue(
            provider_content[0]["text"].startswith("RECENT_CONVERSATION_JSON:")
        )
        self.assertTrue(
            provider_content[1]["text"].startswith("CORE_CONTEXT_V3_JSON:")
        )
        self.assertTrue(
            provider_content[2]["text"].startswith("ORIGINAL_REQUEST_VERBATIM:")
        )
        self.assertEqual(
            sum(
                item["text"].startswith("ORIGINAL_REQUEST_VERBATIM:")
                for item in provider_content
            ),
            1,
        )
        self.assertNotIn("RESPONSE_LANGUAGE", json.dumps(provider_request))
        self.assertNotIn(
            "row_creation_policy",
            provider_content[1]["text"],
        )

    def test_provider_context_disambiguates_clip_and_note_coordinates(self) -> None:
        context = self._core_context()
        context["clips"][0]["start_beat"] = 8
        context["clips"][0]["midi_notes"] = [
            {
                "pitch": 60,
                "start_beat": 1,
                "length_beats": 1,
                "velocity": 0.8,
            }
        ]
        request = {
            "original_request": "Rewrite this MIDI clip.",
            "conversation": [],
            "core_context": context,
            "supported_command_types": {"midi.replace_notes"},
            "resource_refs_enabled": False,
            "capability_surface": v3_server_contract.extract_capability_surface(
                context
            ),
        }

        provider_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
        )
        context_text = provider_request["messages"][0]["content"][1]["text"]
        provider_context = json.loads(context_text.split("\n", 1)[1])
        provider_clip = provider_context["clips"][0]

        self.assertEqual(context["clips"][0]["start_beat"], 8)
        self.assertNotIn("start_beat", provider_clip)
        self.assertEqual(provider_clip["timeline_start_beat"], 8)
        self.assertEqual(
            provider_clip["midi_note_timebase"],
            {"origin_beat": 0, "end_limit_beat": 8},
        )
        self.assertEqual(provider_clip["midi_notes"][0]["start_beat"], 1)

        for resource_refs_enabled, expected_variants in ((False, 1), (True, 2)):
            with self.subTest(resource_refs_enabled=resource_refs_enabled):
                request["resource_refs_enabled"] = resource_refs_enabled
                request["supported_command_types"] = (
                    {"midi.create_clip", "midi.replace_notes"}
                    if resource_refs_enabled
                    else {"midi.replace_notes"}
                )
                provider_request = v3_server_contract.build_provider_request(
                    request,
                    model="server-model",
                    reasoning_effort="low",
                )
                replace_variants = [
                    variant
                    for variant in provider_request["tools"][0]["parameters"]
                    ["properties"]["commands"]["items"]["anyOf"]
                    if variant["properties"]["type"]["enum"]
                    == ["midi.replace_notes"]
                ]
                self.assertEqual(len(replace_variants), 1)
                arguments_schema = replace_variants[0]["properties"]["arguments"]
                argument_variants = arguments_schema.get(
                    "anyOf", [arguments_schema]
                )
                self.assertEqual(len(argument_variants), expected_variants)
                for argument_variant in argument_variants:
                    notes_description = argument_variant["properties"]["notes"][
                        "description"
                    ]
                    self.assertIn(
                        "relative to this clip, never the project timeline",
                        notes_description,
                    )
                    self.assertIn("start_beat + length_beats", notes_description)

    def test_dynamic_capacity_is_versioned_and_authenticated(self) -> None:
        paid_context = self._dynamic_context(row_count=101)
        paid = v3_server_contract.extract_capability_surface(
            paid_context,
            authenticated_subscription_tier="pro",
        )
        self.assertIsNone(paid.maximum_rows)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Created another row.",
            "commands": [{
                "command_id": "row-102",
                "type": "row.create",
                "arguments": {
                    "name": "Row 102",
                    "lane": {"kind": "audio"},
                    "position": {"kind": "end"},
                },
            }],
            "question_options": [],
        }
        self.assertEqual(
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=paid,
            ),
            plan,
        )

        server_clamped_free = v3_server_contract.extract_capability_surface(
            paid_context,
            authenticated_subscription_tier="free",
        )
        self.assertEqual(server_clamped_free.maximum_rows, 5)
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=server_clamped_free,
            )
        self.assertEqual(raised.exception.code, "v3_plan_row_capacity_exceeded")

        request = {
            "original_request": "Add a row.",
            "conversation": [],
            "core_context": paid_context,
            "supported_command_types": {"row.create"},
            "resource_refs_enabled": False,
            "capability_surface": paid,
        }
        provider_request = v3_server_contract.build_provider_request(
            request,
            model="server-model",
            reasoning_effort="low",
        )
        self.assertIn(
            "null means there is no product-defined row creation limit",
            provider_request["instructions"],
        )
        self.assertNotIn(
            "must not exceed a known max_rows",
            provider_request["instructions"],
        )
        self.assertNotEqual(
            v3_server_contract.contract_fingerprint(
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=paid,
            ),
            v3_server_contract.contract_fingerprint(
                command_types={"row.create"},
                resource_refs_enabled=False,
                capability_surface=server_clamped_free,
            ),
        )

    def test_dynamic_free_capacity_follows_ordered_creation_policy(self) -> None:
        create = {
            "command_id": "create-row",
            "type": "row.create",
            "arguments": {
                "name": "Replacement",
                "lane": {"kind": "audio"},
                "position": {"kind": "end"},
            },
        }

        four_rows = v3_server_contract.extract_capability_surface(
            self._dynamic_context(row_count=4, free=True),
            authenticated_subscription_tier="free",
        )
        self.assertEqual(
            v3_server_contract.validate_plan_capabilities(
                {"commands": [create]}, four_rows
            )["row_count"],
            5,
        )

        five_rows = v3_server_contract.extract_capability_surface(
            self._dynamic_context(row_count=5, free=True),
            authenticated_subscription_tier="free",
        )
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [create]}, five_rows
            )
        self.assertEqual(raised.exception.code, "v3_plan_row_capacity_exceeded")

        delete_then_create = [
            {
                "command_id": "delete-row",
                "type": "row.delete",
                "arguments": {"row_id": 1},
            },
            create,
        ]
        self.assertEqual(
            v3_server_contract.validate_plan_capabilities(
                {"commands": delete_then_create}, five_rows
            )["row_count"],
            5,
        )

        oversized = v3_server_contract.extract_capability_surface(
            self._dynamic_context(row_count=6, free=True),
            authenticated_subscription_tier="free",
        )
        self.assertEqual(
            v3_server_contract.validate_plan_capabilities(
                {"commands": self._transport_restart_plan()["commands"]},
                oversized,
            )["row_count"],
            6,
        )

    def test_dynamic_context_uses_expanded_envelope_without_sampling(self) -> None:
        context = self._dynamic_context(row_count=120)
        context["clips"] = [
            {
                "clip_id": f"clip-{index:04d}",
                "row_id": index % 120 + 1,
                "kind": "audio",
                "source_available": True,
            }
            for index in range(600)
        ]
        context["padding"] = ["x" * 30_000] * 7
        body = {
            "request_contract": v3_server_contract.REQUEST_CONTRACT,
            "original_request": "Inspect the complete project.",
            "conversation": [],
            "core_context": context,
            "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
            "supported_command_types": ["transport.restart"],
            "resource_refs_enabled": False,
        }
        raw_bytes = len(json.dumps(body).encode("utf-8"))
        self.assertGreater(raw_bytes, v3_server_contract.MAX_REQUEST_BYTES)
        validated = v3_server_contract.validate_context_request(
            body,
            raw_body_bytes=raw_bytes,
            authenticated_subscription_tier="pro",
        )
        self.assertEqual(len(validated["capability_surface"].rows), 120)
        self.assertEqual(len(validated["capability_surface"].clips), 600)

        legacy = copy.deepcopy(body)
        project = legacy["core_context"]["project"]
        project.pop("project_capacity_policy")
        project["row_capacity"] = {
            "current_rows": 120,
            "max_rows": 120,
            "can_create": False,
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_context_request(
                legacy,
                raw_body_bytes=len(json.dumps(legacy).encode("utf-8")),
            )
        self.assertEqual(raised.exception.code, "v3_context_request_limit")

    def test_dynamic_envelope_boundaries_are_inclusive(self) -> None:
        context = self._dynamic_context()
        body = {
            "request_contract": v3_server_contract.REQUEST_CONTRACT,
            "original_request": "Inspect.",
            "conversation": [],
            "core_context": context,
            "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
            "supported_command_types": ["transport.restart"],
            "resource_refs_enabled": False,
        }
        raw_bytes = len(json.dumps(body).encode("utf-8"))
        core_bytes = len(
            json.dumps(
                context,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
        )
        with mock.patch.object(
            v3_server_contract, "DYNAMIC_MAX_REQUEST_BYTES", raw_bytes
        ), mock.patch.object(
            v3_server_contract, "DYNAMIC_MAX_CORE_CONTEXT_BYTES", core_bytes
        ):
            v3_server_contract.validate_context_request(
                body,
                raw_body_bytes=raw_bytes,
                authenticated_subscription_tier="pro",
            )
            with self.assertRaises(v3_server_contract.V3ContractError):
                v3_server_contract.validate_context_request(
                    body,
                    raw_body_bytes=raw_bytes + 1,
                    authenticated_subscription_tier="pro",
                )
        with mock.patch.object(
            v3_server_contract, "DYNAMIC_MAX_CORE_CONTEXT_BYTES", core_bytes - 1
        ):
            with self.assertRaises(v3_server_contract.V3ContractError):
                v3_server_contract.validate_context_request(
                    body,
                    raw_body_bytes=raw_bytes,
                    authenticated_subscription_tier="pro",
                )

        for limit_name, value in (
            ("MAX_CONTEXT_NODES", {"items": [None, None, None, None]}),
            ("MAX_COLLECTION_ITEMS", [None, None, None, None]),
            ("MAX_CONTEXT_TOTAL_STRING_CHARS", {"a": "12345", "b": "678901"}),
        ):
            with self.subTest(limit_name=limit_name), mock.patch.object(
                v3_server_contract, limit_name, 3 if "STRING" not in limit_name else 10
            ):
                with self.assertRaises(v3_server_contract.V3ContractError):
                    v3_server_contract._validate_context_value(
                        value, expanded_capacity=False
                    )
                v3_server_contract._validate_context_value(
                    value, expanded_capacity=True
                )

    def test_dynamic_context_aggregate_counts_do_not_beat_byte_budget(self) -> None:
        context = self._dynamic_context()
        context["padding"] = [None] * 250_001
        body = {
            "request_contract": v3_server_contract.REQUEST_CONTRACT,
            "original_request": "Inspect.",
            "conversation": [],
            "core_context": context,
            "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
            "supported_command_types": ["transport.restart"],
            "resource_refs_enabled": False,
        }
        raw_bytes = len(v3_server_contract._canonical_json(body).encode("utf-8"))
        core_bytes = len(
            v3_server_contract._canonical_json(context).encode("utf-8")
        )

        self.assertLess(core_bytes, v3_server_contract.DYNAMIC_MAX_CORE_CONTEXT_BYTES)
        self.assertLess(raw_bytes, v3_server_contract.DYNAMIC_MAX_REQUEST_BYTES)
        validated = v3_server_contract.validate_context_request(
            body,
            raw_body_bytes=raw_bytes,
        )
        self.assertEqual(len(validated["core_context"]["padding"]), 250_001)

    def test_unknown_or_malformed_capacity_policy_never_unlocks_creation(self) -> None:
        unknown = self._dynamic_context()
        unknown["project"]["project_capacity_policy"] = "future-policy"
        with self.assertRaises(v3_server_contract.V3ContractError):
            v3_server_contract.extract_capability_surface(unknown)

        malformed = self._dynamic_context()
        malformed["project"]["row_capacity"]["creation_limit"] = 1000
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(malformed)
        self.assertEqual(raised.exception.code, "v3_capability_context_invalid")

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

    def test_semantic_effect_validation_rejects_wrong_ids_and_pairing(self) -> None:
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
                self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_semantic_effect_validation_accepts_exact_ids_ranges_and_defaults(self) -> None:
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
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

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

    def test_semantic_validation_rejects_replacement_notes_past_clip_end(
        self,
    ) -> None:
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Rewrote the percussion part.",
            "commands": [
                {
                    "command_id": "replace-percussion",
                    "type": "midi.replace_notes",
                    "arguments": {
                        "clip_id": "clip-1",
                        "notes": [
                            {
                                "pitch": 60,
                                "start_beat": 7.5,
                                "length_beats": 1.0,
                                "velocity": 0.8,
                            }
                        ],
                    },
                }
            ],
            "question_options": [],
        }

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"midi.replace_notes"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
            )

        self.assertEqual(raised.exception.code, "v3_plan_midi_note_out_of_bounds")

    def test_replacement_boundary_preserves_microsecond_context_precision(self) -> None:
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Replaced the notes.",
            "question_options": [],
            "commands": [{
                "command_id": "replace", "type": "midi.replace_notes",
                "arguments": {"clip_id": "clip-1", "notes": [{
                    "pitch": 66, "start_beat": 31, "length_beats": 1,
                    "velocity": 0.8,
                }]},
            }],
        }
        # At 108 BPM, whole-ms storage reproduces the observed 31.9986 boundary.
        for length, accepted in (
            (17777 / 1000 * 108 / 60, False),
            (17777778 / 1000000 * 108 / 60, True),
            (32 - 0.0014, False),
            (31.75, False),
        ):
            with self.subTest(length=length):
                context = self._core_context()
                context["clips"][0]["length_beats"] = length
                surface = v3_server_contract.extract_capability_surface(context)
                def validate():
                    return v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(plan),
                        command_types={"midi.replace_notes"},
                        resource_refs_enabled=False,
                        capability_surface=surface,
                    )
                if accepted:
                    validate()
                else:
                    with self.assertRaises(v3_server_contract.V3ContractError) as raised:
                        validate()
                    self.assertEqual(raised.exception.code, "v3_plan_midi_note_out_of_bounds")

    def test_gated_midi_boundary_extension(self):
        import copy
        for marker in (None, 'unknown', 'extend_1ms_v1'):
            for refs in (False, True):
                context = self._core_context()
                context['project'].update(bpm=108, midi_boundary_policy=marker)
                context['clips'][0]['length_beats'] = 31.9986
                plan = {
                    'schema_version': 'plan_v3_prototype_2', 'outcome': 'plan',
                    'user_message': 'Replaced notes.', 'question_options': [],
                    'commands': [{'command_id': 'one', 'type': 'midi.replace_notes',
                        'arguments': {'clip_id': 'clip-1', 'notes': [
                            {'pitch': 60, 'start_beat': 31, 'length_beats': 1, 'velocity': .8}]}}],
                }
                def validate(p):
                    return v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(p), command_types={'midi.replace_notes'},
                        resource_refs_enabled=refs,
                        capability_surface=v3_server_contract.extract_capability_surface(context))
                with self.subTest(marker=marker, refs=refs):
                    if marker != 'extend_1ms_v1':
                        with self.assertRaises(v3_server_contract.V3ContractError): validate(plan)
                        continue
                    original = copy.deepcopy(plan)
                    validate(plan)
                    self.assertEqual(plan, original)
                    next_command = copy.deepcopy(plan['commands'][0])
                    next_command['command_id'] = 'two'
                    next_command['arguments']['notes'][0]['start_beat'] = 31.001
                    plan['commands'].append(next_command)
                    with self.assertRaises(v3_server_contract.V3ContractError): validate(plan)

    def test_pitch_diagnostics_follow_ordered_instrument_changes(self):
        context = self._core_context()
        context['instruments'].append('limited-guitar')
        context['instrument_catalog'].append({'instrument_id': 'limited-guitar',
            'name': 'Guitar', 'playable_pitch_ranges': [{'low': 40, 'high': 86}]})
        plan = {'schema_version': 'plan_v3_prototype_2', 'outcome': 'plan',
            'user_message': 'Created music.', 'question_options': [], 'commands': [
                {'command_id': 'switch', 'type': 'row.set_instrument',
                 'arguments': {'row_id': 101, 'instrument_id': 'limited-guitar'}},
                {'command_id': 'create', 'type': 'midi.create_clip',
                 'arguments': {'destination': {'row_id': 101}, 'start_beat': 0,
                    'length_beats': 32, 'notes': [
                        {'pitch': p, 'start_beat': 0, 'length_beats': 1, 'velocity': .8}
                        for p in (36, 38, 36)]}}]}
        with self.assertRaises(v3_server_contract.V3ContractError) as caught:
            v3_server_contract.parse_and_validate_provider_plan(self._provider_payload(plan),
                command_types={'row.set_instrument', 'midi.create_clip'},
                resource_refs_enabled=True,
                capability_surface=v3_server_contract.extract_capability_surface(context))
        self.assertEqual(caught.exception.repair_details, {
            'command_index': 1, 'command_type': 'midi.create_clip',
            'effective_instrument_id': 'limited-guitar', 'rejected_pitches': [36, 38],
            'playable_pitch_ranges': [{'low': 40, 'high': 86}]})

    def test_pitch_feedback_preserves_range_gaps_and_endpoints(self):
        for ranges, pitches, rejected in (
            ([{'low': 40, 'high': 86}], [40, 86], []),
            ([{'low': 40, 'high': 86}], [36, 38, 87, 36], [36, 38, 87]),
            ([{'low': 36, 'high': 38}, {'low': 42, 'high': 42}], [36, 38, 42], []),
            ([{'low': 36, 'high': 38}, {'low': 42, 'high': 42}], [39, 41], [39, 41]),
            ([], [0, 127], []),
        ):
            for generated in (False, True):
                with self.subTest(ranges=ranges, pitches=pitches, generated=generated):
                    context = self._core_context()
                    context['instrument_catalog'][0]['playable_pitch_ranges'] = ranges
                    commands = []
                    destination = {'row_id': 101}
                    if generated:
                        commands.append({'command_id': 'row', 'type': 'row.create',
                            'arguments': {'name': 'Music', 'position': {'kind': 'end'},
                                'lane': {'kind': 'midi', 'instrument_id': 'free-piano'}}})
                        destination = {'row_ref': {'command_id': 'row', 'output': 'row'}}
                    commands.append({'command_id': 'create', 'type': 'midi.create_clip',
                        'arguments': {'destination': destination, 'start_beat': 0,
                            'length_beats': 32, 'notes': [{'pitch': p, 'start_beat': 0,
                                'length_beats': 1, 'velocity': .8} for p in pitches]}})
                    plan = {'schema_version': 'plan_v3_prototype_2', 'outcome': 'plan',
                        'user_message': 'Created music.', 'question_options': [],
                        'commands': commands}
                    def validate():
                        return v3_server_contract.parse_and_validate_provider_plan(
                            self._provider_payload(plan),
                            command_types={'row.create', 'midi.create_clip'},
                            resource_refs_enabled=True,
                            capability_surface=v3_server_contract.extract_capability_surface(context))
                    if not rejected:
                        validate()
                    else:
                        with self.assertRaises(v3_server_contract.V3ContractError) as caught:
                            validate()
                        self.assertEqual(caught.exception.code, 'v3_plan_midi_pitch_unavailable')
                        self.assertEqual(caught.exception.repair_details, {
                            'command_index': int(generated), 'command_type': 'midi.create_clip',
                            'effective_instrument_id': 'free-piano', 'rejected_pitches': rejected,
                            'playable_pitch_ranges': ranges})

    def test_semantic_validation_rejects_phone_cleanup_sound_conflicts(self) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._phone_cleanup_context()
        )
        conflicting_commands = [
            {
                "command_id": "ensure-effect",
                "type": "effect.ensure_configured",
                "arguments": {
                    "row_id": 101,
                    "effect_id": "Reverb",
                    "parameters": [],
                },
            },
            {
                "command_id": "remove-effect",
                "type": "effect.remove",
                "arguments": {"effect_instance_id": "cleanup-row-effect"},
            },
            {
                "command_id": "bypass-effect",
                "type": "effect.set_bypassed",
                "arguments": {
                    "effect_instance_id": "cleanup-row-effect",
                    "bypassed": True,
                },
            },
            self._mix_command({"scope": "row", "row_id": 101}),
            self._mix_command({"scope": "group", "group_id": "cleanup-row"}),
            self._mix_command({"scope": "all_rows"}),
        ]
        command_types = {
            "row.apply_phone_mic_cleanup",
            "effect.ensure_configured",
            "effect.remove",
            "effect.set_bypassed",
            "mix.apply_goal",
        }

        for conflicting_command in conflicting_commands:
            with self.subTest(command_type=conflicting_command["type"]):
                with self.assertRaises(
                    v3_server_contract.V3ContractError
                ) as raised:
                    v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(
                            self._phone_cleanup_plan(conflicting_command)
                        ),
                        command_types=command_types,
                        resource_refs_enabled=False,
                        capability_surface=surface,
                    )
                self.assertEqual(
                    raised.exception.code,
                    "v3_plan_phone_cleanup_effect_conflict",
                )

    def test_semantic_validation_allows_independent_phone_cleanup_operations(
        self,
    ) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._phone_cleanup_context()
        )
        independent_commands = [
            None,
            self._mix_command({"scope": "row", "row_id": 103}),
            self._mix_command({"scope": "group", "group_id": "other-row"}),
            self._mix_command({"scope": "master"}),
            {
                "command_id": "ensure-other-effect",
                "type": "effect.ensure_configured",
                "arguments": {
                    "row_id": 103,
                    "effect_id": "Reverb",
                    "parameters": [],
                },
            },
        ]
        command_types = {
            "row.apply_phone_mic_cleanup",
            "effect.ensure_configured",
            "mix.apply_goal",
        }

        for independent_command in independent_commands:
            with self.subTest(command=independent_command):
                plan = self._phone_cleanup_plan(independent_command)
                validated = v3_server_contract.parse_and_validate_provider_plan(
                    self._provider_payload(plan),
                    command_types=command_types,
                    resource_refs_enabled=False,
                    capability_surface=surface,
                )
                self.assertEqual(validated, plan)

    def test_semantic_validation_rejects_cleanup_row_in_generated_mix_group(
        self,
    ) -> None:
        surface = v3_server_contract.extract_capability_surface(
            self._phone_cleanup_context()
        )
        plan = self._phone_cleanup_plan()
        plan["commands"].extend(
            [
                {
                    "command_id": "create-cleanup-group",
                    "type": "group.create",
                    "arguments": {
                        "members": [{"row_id": 101}, {"row_id": 102}],
                        "name": "Cleanup Group",
                    },
                },
                self._mix_command(
                    {
                        "scope": "group",
                        "group_ref": {
                            "command_id": "create-cleanup-group",
                            "output": "group",
                        },
                    }
                ),
            ]
        )

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={
                    "row.apply_phone_mic_cleanup",
                    "group.create",
                    "mix.apply_goal",
                },
                resource_refs_enabled=True,
                capability_surface=surface,
            )

        self.assertEqual(
            raised.exception.code,
            "v3_plan_phone_cleanup_effect_conflict",
        )

    def test_phone_cleanup_semantic_policy_participates_in_fingerprint(self) -> None:
        kwargs = {
            "command_types": {"row.apply_phone_mic_cleanup"},
            "resource_refs_enabled": False,
            "capability_surface": v3_server_contract.extract_capability_surface(
                self._phone_cleanup_context()
            ),
        }
        first = v3_server_contract.contract_fingerprint(**kwargs)
        with mock.patch.object(
            v3_server_contract,
            "_PHONE_CLEANUP_CONFLICT_POLICY_VERSION",
            "phone_cleanup_conflict_test_version",
        ):
            second = v3_server_contract.contract_fingerprint(**kwargs)

        self.assertNotEqual(first, second)

    def test_typed_clip_state_policy_participates_in_fingerprint(self) -> None:
        kwargs = {
            "command_types": {"midi.create_clip", "midi.transpose"},
            "resource_refs_enabled": True,
            "capability_surface": self._surface(),
        }
        first = v3_server_contract.contract_fingerprint(**kwargs)
        with mock.patch.object(
            v3_server_contract,
            "_TYPED_CLIP_STATE_POLICY_VERSION",
            "ordered_typed_clip_reference_test_version",
        ):
            second = v3_server_contract.contract_fingerprint(**kwargs)

        self.assertNotEqual(first, second)

    def test_group_state_policy_participates_in_fingerprint(self) -> None:
        kwargs = {
            "command_types": {"group.create", "group.remove_row"},
            "resource_refs_enabled": True,
            "capability_surface": self._group_surface(members=[1, 2]),
        }
        first = v3_server_contract.contract_fingerprint(**kwargs)
        with mock.patch.object(
            v3_server_contract,
            "_GROUP_STATE_POLICY_VERSION",
            "ordered_group_lifecycle_test_version",
        ):
            second = v3_server_contract.contract_fingerprint(**kwargs)

        self.assertNotEqual(first, second)

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

    def test_effect_catalog_is_bounded_by_bytes_not_legacy_count(self) -> None:
        context = self._core_context()
        context["effects"] = [
            {"effect_id": f"Effect {index}", "parameters": []}
            for index in range(65)
        ]

        surface = v3_server_contract.extract_capability_surface(context)
        tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=surface,
        )

        self.assertEqual(len(surface.effects), 65)
        self.assertLess(
            len(v3_server_contract._canonical_json(tool).encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

    def test_effect_parameters_are_bounded_by_bytes_not_legacy_count(self) -> None:
        context = self._core_context()
        context["effects"][0]["parameters"] = [
            {"parameter_id": f"Parameter {index}", "range": [0, 1]}
            for index in range(17)
        ]

        surface = v3_server_contract.extract_capability_surface(context)
        tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=surface,
        )

        self.assertEqual(len(surface.effect_by_id["Distortion"].parameters), 17)
        self.assertLess(
            len(v3_server_contract._canonical_json(tool).encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

    def test_filesystem_backed_instrument_ids_use_request_byte_budget(self) -> None:
        instrument_ids = (
            "/Library/Audio/Plug-Ins/VST3/"
            + "/Deeply Nested Vendor Folder" * 8
            + "/Large Instrument.vst3",
            "sfz_asset:/Users/customer/Music/Mixroom/Generated Samplers/"
            + "/Long Project Folder" * 8
            + "/instrument.sfz",
        )

        for instrument_id in instrument_ids:
            with self.subTest(instrument_id=instrument_id):
                self.assertGreater(
                    len(instrument_id), v3_server_contract.MAX_IDENTIFIER_CHARS
                )
                context = self._core_context()
                context["rows"][0]["instrument_id"] = instrument_id
                context["clips"][0]["instrument_id"] = instrument_id
                context["instruments"] = [instrument_id]
                context["instrument_catalog"] = [
                    {
                        "instrument_id": instrument_id,
                        "name": "Filesystem-backed instrument",
                        "playable_pitch_ranges": [{"low": 0, "high": 127}],
                    }
                ]
                body = {
                    "request_contract": v3_server_contract.REQUEST_CONTRACT,
                    "original_request": "Keep using this instrument.",
                    "conversation": [],
                    "core_context": context,
                    "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
                    "supported_command_types": ["row.set_instrument"],
                    "resource_refs_enabled": False,
                }

                validated_request = v3_server_contract.validate_context_request(
                    body,
                    raw_body_bytes=len(
                        v3_server_contract._canonical_json(body).encode("utf-8")
                    ),
                )
                surface = validated_request["capability_surface"]
                self.assertEqual(surface.instrument_ids, frozenset({instrument_id}))
                self.assertIn(instrument_id, surface.instrument_by_id)

                plan = {
                    "schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
                    "outcome": "plan",
                    "user_message": "Kept the selected instrument.",
                    "commands": [
                        {
                            "command_id": "keep-instrument",
                            "type": "row.set_instrument",
                            "arguments": {
                                "row_id": 101,
                                "instrument_id": instrument_id,
                            },
                        }
                    ],
                    "question_options": [],
                }
                for resource_refs_enabled in (False, True):
                    with self.subTest(
                        instrument_id=instrument_id,
                        resource_refs_enabled=resource_refs_enabled,
                    ):
                        validated_plan = (
                            v3_server_contract.parse_and_validate_provider_plan(
                                self._provider_payload(plan),
                                command_types={"row.set_instrument"},
                                resource_refs_enabled=resource_refs_enabled,
                                capability_surface=surface,
                            )
                        )
                        self.assertEqual(validated_plan, plan)

                        invented_plan = copy.deepcopy(plan)
                        invented_plan["commands"][0]["arguments"][
                            "instrument_id"
                        ] = instrument_id + ".invented"
                        with self.assertRaises(
                            v3_server_contract.V3ContractError
                        ) as raised:
                            v3_server_contract.parse_and_validate_provider_plan(
                                self._provider_payload(invented_plan),
                                command_types={"row.set_instrument"},
                                resource_refs_enabled=resource_refs_enabled,
                                capability_surface=surface,
                            )
                        self.assertEqual(
                            raised.exception.code,
                            "v3_plan_capability_invalid",
                        )

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

    def test_preserved_instrument_capability_allows_note_edits_without_selection(self) -> None:
        context = self._free_context_with_preserved_paid_instrument()
        context["instrument_catalog"].append(
            {
                "instrument_id": "paid-orchestral-strings",
                "name": "Orchestral Strings",
                "playable_pitch_ranges": [{"low": 36, "high": 96}],
            }
        )
        surface = v3_server_contract.extract_capability_surface(context)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Rewrote the preserved strings.",
            "commands": [
                {
                    "command_id": "rewrite-preserved",
                    "type": "midi.replace_notes",
                    "arguments": {
                        "clip_id": "clip-paid",
                        "notes": [
                            {
                                "pitch": 60,
                                "start_beat": 0,
                                "length_beats": 1,
                                "velocity": 0.8,
                            }
                        ],
                    },
                }
            ],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"midi.replace_notes"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )

        self.assertEqual(validated, plan)
        self.assertEqual(surface.instrument_ids, frozenset({"free-piano"}))
        self.assertIn("paid-orchestral-strings", surface.instrument_by_id)

    def test_legacy_context_can_edit_preserved_instrument_without_catalog_entry(self) -> None:
        context = self._free_context_with_preserved_paid_instrument()
        surface = v3_server_contract.extract_capability_surface(context)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Changed the existing rhythm.",
            "commands": [
                {
                    "command_id": "rewrite-existing",
                    "type": "midi.replace_notes",
                    "arguments": {
                        "clip_id": "clip-paid",
                        "notes": [
                            {
                                "pitch": 60,
                                "start_beat": 0,
                                "length_beats": 1,
                                "velocity": 0.8,
                            }
                        ],
                    },
                }
            ],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"midi.replace_notes"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )

        self.assertEqual(validated, plan)
        self.assertEqual(surface.instrument_ids, frozenset({"free-piano"}))

    def test_nonselectable_instrument_capability_must_belong_to_existing_state(self) -> None:
        context = self._core_context()
        context["instrument_catalog"].append(
            {
                "instrument_id": "unrelated-paid-instrument",
                "name": "Unrelated Paid Instrument",
                "playable_pitch_ranges": [{"low": 0, "high": 127}],
            }
        )

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.extract_capability_surface(context)

        self.assertEqual(raised.exception.code, "v3_capability_context_invalid")

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
        context = self._free_context_with_preserved_paid_instrument()
        context["instrument_catalog"].append(
            {
                "instrument_id": "paid-orchestral-strings",
                "name": "Orchestral Strings",
                "playable_pitch_ranges": [{"low": 36, "high": 96}],
            }
        )
        surface = v3_server_contract.extract_capability_surface(context)
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
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

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

    def test_runtime_schema_does_not_embed_effect_capabilities(self) -> None:
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"effect.ensure_configured", "row.create"},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
        )
        encoded = json.dumps(tool)
        self.assertIn("Distortion", self._surface().effect_by_id)
        self.assertNotIn('"Distortion"', encoded)
        self.assertNotIn('"HPF Frequency"', encoded)
        self.assertIn("free-piano", self._surface().instrument_ids)
        self.assertNotIn('"free-piano"', encoded)
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

    def test_large_effect_catalog_does_not_expand_runtime_schema(self) -> None:
        small_context = self._core_context()
        large_context = copy.deepcopy(small_context)
        large_context["effects"].extend(
            {
                "effect_id": f"Synthetic Effect {effect_index}",
                "parameters": [
                    {
                        "parameter_id": f"Parameter {parameter_index}",
                        "range": [0, 1],
                    }
                    for parameter_index in range(16)
                ],
            }
            for effect_index in range(64)
        )
        small_surface = v3_server_contract.extract_capability_surface(
            small_context
        )
        large_surface = v3_server_contract.extract_capability_surface(
            large_context
        )

        self.assertLess(
            len(v3_server_contract._canonical_json(large_context).encode("utf-8")),
            v3_server_contract.DYNAMIC_MAX_CORE_CONTEXT_BYTES,
        )
        for resource_refs_enabled in (False, True):
            with self.subTest(resource_refs_enabled=resource_refs_enabled):
                small_tool = v3_server_contract.build_submit_plan_tool(
                    command_types=v3_server_contract.SERVER_COMMAND_TYPES,
                    resource_refs_enabled=resource_refs_enabled,
                    capability_surface=small_surface,
                )
                large_tool = v3_server_contract.build_submit_plan_tool(
                    command_types=v3_server_contract.SERVER_COMMAND_TYPES,
                    resource_refs_enabled=resource_refs_enabled,
                    capability_surface=large_surface,
                )

                self.assertEqual(large_tool, small_tool)
                self.assertLess(
                    len(
                        v3_server_contract._canonical_json(large_tool).encode(
                            "utf-8"
                        )
                    ),
                    v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
                )

    def test_large_library_does_not_expand_runtime_schema(self) -> None:
        context = self._core_context()
        context["rows"][0].update({"lane_kind": "audio", "instrument_id": None})
        context["clips"][0].update(
            {"kind": "audio", "instrument_id": "", "source_available": True}
        )
        context["instruments"] = []
        context["instrument_catalog"] = []
        context["library_assets"] = [
            {"asset_id": f"sample:{index:016x}"} for index in range(20000)
        ]
        surface = v3_server_contract.extract_capability_surface(context)
        single_asset_context = copy.deepcopy(context)
        single_asset_context["library_assets"] = context["library_assets"][:1]
        single_asset_surface = v3_server_contract.extract_capability_surface(
            single_asset_context
        )

        tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        single_asset_tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=single_asset_surface,
        )

        def asset_id_schemas(value):
            if isinstance(value, list):
                for child in value:
                    yield from asset_id_schemas(child)
                return
            if not isinstance(value, dict):
                return
            properties = value.get("properties")
            if isinstance(properties, dict) and isinstance(
                properties.get("asset_id"), dict
            ):
                yield properties["asset_id"]
            for child in value.values():
                yield from asset_id_schemas(child)

        self.assertEqual(tool, single_asset_tool)
        self.assertTrue(list(asset_id_schemas(tool)))
        self.assertTrue(
            all("enum" not in schema for schema in asset_id_schemas(tool))
        )
        self.assertLess(
            len(v3_server_contract._canonical_json(tool).encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

    def test_large_project_resource_ids_do_not_expand_runtime_schema(self) -> None:
        def project_context(resource_count: int) -> dict:
            context = self._dynamic_context(row_count=resource_count)
            instrument_ids = [
                f"instrument-{index}" for index in range(2, resource_count + 1, 2)
            ]
            context["rows"] = [
                {
                    "row_id": index,
                    "lane_kind": "instrument" if index % 2 == 0 else "audio",
                    "instrument_id": (
                        f"instrument-{index}" if index % 2 == 0 else ""
                    ),
                    "mix_processing_supported": True,
                    "has_usable_signal": True,
                    "effects": [{"effect_instance_id": f"effect-instance-{index}"}],
                }
                for index in range(1, resource_count + 1)
            ]
            context["clips"] = [
                {
                    "clip_id": f"clip-{index}",
                    "row_id": index,
                    "kind": "midi" if index % 2 == 0 else "audio",
                    "instrument_id": (
                        f"instrument-{index}" if index % 2 == 0 else ""
                    ),
                    "length_beats": 8,
                    "midi_notes": [],
                }
                for index in range(1, resource_count + 1)
            ]
            context["groups"] = [
                {
                    "group_id": f"group-{index}",
                    "member_row_ids": [index, index + 1],
                }
                for index in range(1, resource_count, 2)
            ]
            context["instruments"] = instrument_ids
            context["instrument_catalog"] = [
                {
                    "instrument_id": instrument_id,
                    "name": instrument_id,
                    "playable_pitch_ranges": [{"low": 0, "high": 127}],
                }
                for instrument_id in instrument_ids
            ]
            return context

        small_context = project_context(2)
        large_context = project_context(3_000)
        large_body = {
            "request_contract": v3_server_contract.REQUEST_CONTRACT,
            "original_request": "Mix the project.",
            "conversation": [],
            "core_context": large_context,
            "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
            "supported_command_types": sorted(
                v3_server_contract.SERVER_COMMAND_TYPES
            ),
            "resource_refs_enabled": True,
        }
        large_body_bytes = len(
            v3_server_contract._canonical_json(large_body).encode("utf-8")
        )
        validated = v3_server_contract.validate_context_request(
            large_body,
            raw_body_bytes=large_body_bytes,
        )
        small_tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=v3_server_contract.extract_capability_surface(
                small_context
            ),
        )
        large_tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=validated["capability_surface"],
        )

        self.assertLess(
            len(v3_server_contract._canonical_json(large_context).encode("utf-8")),
            v3_server_contract.DYNAMIC_MAX_CORE_CONTEXT_BYTES,
        )
        self.assertEqual(large_tool, small_tool)
        self.assertLess(
            len(v3_server_contract._canonical_json(large_tool).encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

        identifier_fields = {
            "asset_id",
            "clip_id",
            "effect_instance_id",
            "group_id",
            "instrument_id",
            "row_id",
        }

        def identifier_schemas(value):
            if isinstance(value, list):
                for child in value:
                    yield from identifier_schemas(child)
                return
            if not isinstance(value, dict):
                return
            properties = value.get("properties")
            if isinstance(properties, dict):
                for name in identifier_fields:
                    schema = properties.get(name)
                    if isinstance(schema, dict):
                        yield name, schema
                row_ids = properties.get("row_ids")
                if isinstance(row_ids, dict) and isinstance(
                    row_ids.get("items"), dict
                ):
                    yield "row_ids", row_ids["items"]
            for child in value.values():
                yield from identifier_schemas(child)

        schemas = list(identifier_schemas(large_tool))
        self.assertTrue(identifier_fields.issubset({name for name, _ in schemas}))
        self.assertTrue(all("enum" not in schema for _, schema in schemas))

    def test_library_asset_ids_are_still_validated_at_runtime(self) -> None:
        context = self._core_context()
        context["rows"][0].update({"lane_kind": "audio", "instrument_id": None})
        context["clips"][0].update(
            {"kind": "audio", "instrument_id": "", "source_available": True}
        )
        context["instruments"] = []
        context["instrument_catalog"] = []
        surface = v3_server_contract.extract_capability_surface(context)

        def plan(asset_id: str) -> dict:
            return {
                "schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
                "outcome": "plan",
                "user_message": "Replaced the sample.",
                "commands": [
                    {
                        "command_id": "replace-sample",
                        "type": "sample.replace",
                        "arguments": {
                            "clip_id": "clip-1",
                            "asset_id": asset_id,
                        },
                    }
                ],
                "question_options": [],
            }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan("asset-1")),
            command_types={"sample.replace"},
            resource_refs_enabled=False,
            capability_surface=surface,
        )
        self.assertEqual(validated, plan("asset-1"))

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan("invented-asset")),
                command_types={"sample.replace"},
                resource_refs_enabled=False,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_large_selectable_instrument_catalog_fits_runtime_schema(self) -> None:
        context = self._dynamic_context()
        instrument_ids = [f"instrument-{index:03d}" for index in range(452)]
        context["instruments"] = instrument_ids
        context["instrument_catalog"] = [
            {
                "instrument_id": instrument_id,
                "name": f"Instrument {index}",
                "playable_pitch_ranges": [{"low": 0, "high": 127}],
            }
            for index, instrument_id in enumerate(instrument_ids)
        ]
        body = {
            "request_contract": v3_server_contract.REQUEST_CONTRACT,
            "original_request": "Create an instrument row.",
            "conversation": [],
            "core_context": context,
            "plan_schema_version": v3_server_contract.PLAN_SCHEMA_VERSION,
            "supported_command_types": sorted(
                v3_server_contract.SERVER_COMMAND_TYPES
            ),
            "resource_refs_enabled": True,
        }
        validated = v3_server_contract.validate_context_request(
            body,
            raw_body_bytes=len(
                v3_server_contract._canonical_json(body).encode("utf-8")
            ),
        )

        tool = v3_server_contract.build_submit_plan_tool(
            command_types=v3_server_contract.SERVER_COMMAND_TYPES,
            resource_refs_enabled=True,
            capability_surface=validated["capability_surface"],
        )

        self.assertEqual(
            validated["capability_surface"].instrument_ids,
            frozenset(instrument_ids),
        )
        self.assertLess(
            len(v3_server_contract._canonical_json(tool).encode("utf-8")),
            v3_server_contract.MAX_RUNTIME_TOOL_BYTES,
        )

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

    def test_row_deletion_retires_its_effect_instances_in_order(self) -> None:
        context = self._core_context()
        context["project"]["row_capacity"]["current_rows"] = 2
        context["rows"].append(
            {
                "row_id": 102,
                "lane_kind": "audio",
                "mix_processing_supported": True,
                "has_usable_signal": False,
                "effects": [],
            }
        )
        surface = v3_server_contract.extract_capability_surface(context)
        delete_row = {
            "command_id": "delete-row",
            "type": "row.delete",
            "arguments": {"row_id": 101},
        }
        remove_effect = {
            "command_id": "remove-effect",
            "type": "effect.remove",
            "arguments": {"effect_instance_id": "fx-1"},
        }

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [delete_row, remove_effect]}, surface
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

        result = v3_server_contract.validate_plan_capabilities(
            {"commands": [remove_effect, delete_row]}, surface
        )
        self.assertEqual(result["row_count"], 1)

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
            100 * 1024,
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

    def test_provider_visible_text_rejects_private_context_markers(self) -> None:
        captured_escape = json.loads(
            PRIVATE_CONTEXT_ESCAPE_FIXTURE.read_text(encoding="utf-8")
        )["user_message"]
        markers = (
            captured_escape,
            "recent_conversation_json:",
            "Core_Context_V3_Json:",
            "semantic_repair_required",
        )
        for marker in markers:
            with self.subTest(marker=marker, field="user_message"):
                plan = self._effect_plan("Distortion", [])
                plan["user_message"] = f"{marker}\nUpdated the sound."
                with self.assertRaises(
                    v3_server_contract.V3ContractError
                ) as raised:
                    v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(plan),
                        command_types={"effect.ensure_configured"},
                        resource_refs_enabled=False,
                        capability_surface=self._surface(),
                        original_request="Add distortion.",
                    )
                self.assertEqual(
                    raised.exception.code,
                    "v3_plan_user_visible_text_unsafe",
                )

            with self.subTest(marker=marker, field="question_options"):
                plan = {
                    "schema_version": "plan_v3_prototype_2",
                    "outcome": "clarify",
                    "user_message": "Which guitar should I change?",
                    "commands": [],
                    "question_options": ["Lead Guitar", marker],
                }
                with self.assertRaises(
                    v3_server_contract.V3ContractError
                ) as raised:
                    v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(plan),
                        command_types={"effect.ensure_configured"},
                        resource_refs_enabled=False,
                        capability_surface=self._surface(),
                        original_request="Change the guitar.",
                    )
                self.assertEqual(
                    raised.exception.code,
                    "v3_plan_user_visible_text_unsafe",
                )

    def test_successful_plan_rejects_verbatim_original_request_as_summary(self) -> None:
        original_request = "  Add   distortion, EQ, and light reverb!  "
        plan = self._effect_plan("Distortion", [])
        plan["user_message"] = "Add distortion, EQ, and light reverb!"

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"effect.ensure_configured"},
                resource_refs_enabled=False,
                capability_surface=self._surface(),
                original_request=original_request,
            )

        self.assertEqual(
            raised.exception.code,
            "v3_plan_user_visible_text_unsafe",
        )

    def test_provider_visible_text_allows_natural_technical_response(self) -> None:
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "respond",
            "user_message": (
                "A compressor reduces dynamic range by turning down louder parts "
                "above its threshold."
            ),
            "commands": [],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"effect.ensure_configured"},
            resource_refs_enabled=False,
            capability_surface=self._surface(),
            original_request="What does a compressor do?",
        )

        self.assertEqual(validated, plan)

    def test_user_visible_text_policy_participates_in_fingerprint(self) -> None:
        kwargs = {
            "command_types": {"effect.ensure_configured"},
            "resource_refs_enabled": False,
            "capability_surface": self._surface(),
        }
        first = v3_server_contract.contract_fingerprint(**kwargs)
        with mock.patch.object(
            v3_server_contract,
            "_USER_VISIBLE_TEXT_POLICY_VERSION",
            "user_visible_text_test_version",
        ):
            second = v3_server_contract.contract_fingerprint(**kwargs)

        self.assertNotEqual(first, second)

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

    def test_runtime_schema_does_not_embed_typed_target_ids(self) -> None:
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
        self.assertNotIn('"enum": [2]', encoded_by_type["row.set_instrument"])
        self.assertNotIn('"enum": [1, 2]', encoded_by_type["row.set_instrument"])
        self.assertNotIn(
            '"enum": ["midi-clip"]', encoded_by_type["midi.replace_notes"]
        )
        self.assertNotIn("audio-clip", encoded_by_type["midi.replace_notes"])

    def test_runtime_schema_prunes_direct_audio_target_when_only_midi_exists(self) -> None:
        surface = v3_server_contract.extract_capability_surface(self._core_context())
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"sample.place", "clip.set_timeline_length_beats"},
            resource_refs_enabled=True,
            capability_surface=surface,
        )

        variant = self._runtime_command_variant(
            tool, "clip.set_timeline_length_beats"
        )
        self.assertIsNotNone(variant)
        encoded = json.dumps(variant)
        self.assertIn('"clip_ref"', encoded)
        self.assertNotIn('"clip_id"', encoded)

    def test_runtime_schema_keeps_direct_audio_target_without_embedding_ids(self) -> None:
        context = self._core_context()
        context["project"]["row_capacity"]["current_rows"] = 2
        context["rows"].append(
            {
                "row_id": 102,
                "lane_kind": "audio",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            }
        )
        context["clips"].append(
            {
                "clip_id": "audio-clip",
                "row_id": 102,
                "kind": "audio",
                "length_beats": 8,
            }
        )
        surface = v3_server_contract.extract_capability_surface(context)
        tool = v3_server_contract.build_submit_plan_tool(
            command_types={"sample.place", "clip.set_timeline_length_beats"},
            resource_refs_enabled=True,
            capability_surface=surface,
        )

        variant = self._runtime_command_variant(
            tool, "clip.set_timeline_length_beats"
        )
        self.assertIsNotNone(variant)
        encoded = json.dumps(variant)
        self.assertIn('"clip_ref"', encoded)
        self.assertIn('"clip_id"', encoded)
        self.assertNotIn('"enum": ["audio-clip"]', encoded)
        self.assertNotIn('"enum": ["clip-1"]', encoded)

    def test_runtime_schema_preserves_generated_clip_consumers(self) -> None:
        context = self._core_context()
        context["clips"] = []
        context["rows"][0].update(
            {"mix_processing_supported": False, "has_usable_signal": False}
        )
        surface = v3_server_contract.extract_capability_surface(context)
        command_types = {
            "midi.create_clip",
            "midi.replace_notes",
            "midi.append_notes",
            "midi.chop_notes",
            "midi.transpose",
            "sample.place",
            "clip.adjust_pitch_semitones",
        }

        ref_tool = v3_server_contract.build_submit_plan_tool(
            command_types=command_types,
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        ref_types = {
            variant["properties"]["type"]["enum"][0]
            for variant in ref_tool["parameters"]["properties"]["commands"][
                "items"
            ]["anyOf"]
        }
        self.assertTrue(command_types.issubset(ref_types))
        for command_type in {
            "midi.replace_notes",
            "midi.append_notes",
            "midi.chop_notes",
            "midi.transpose",
            "clip.adjust_pitch_semitones",
        }:
            variant = self._runtime_command_variant(ref_tool, command_type)
            self.assertIsNotNone(variant)
            encoded = json.dumps(variant)
            self.assertIn('"clip_ref"', encoded)
            self.assertNotIn('"clip_id"', encoded)

        direct_tool = v3_server_contract.build_submit_plan_tool(
            command_types=command_types,
            resource_refs_enabled=False,
            capability_surface=surface,
        )
        direct_types = {
            variant["properties"]["type"]["enum"][0]
            for variant in direct_tool["parameters"]["properties"]["commands"][
                "items"
            ]["anyOf"]
        }
        self.assertEqual(
            direct_types,
            {"midi.create_clip", "sample.place"},
        )

    def test_runtime_schema_rejects_orphan_generated_clip_consumers(self) -> None:
        context = self._core_context()
        context["clips"] = []
        context["library_assets"] = []
        context["rows"][0].update(
            {"mix_processing_supported": False, "has_usable_signal": False}
        )
        surface = v3_server_contract.extract_capability_surface(context)

        tool = v3_server_contract.build_submit_plan_tool(
            command_types={
                "row.create",
                "midi.transpose",
                "clip.adjust_pitch_semitones",
            },
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        command_types = {
            variant["properties"]["type"]["enum"][0]
            for variant in tool["parameters"]["properties"]["commands"][
                "items"
            ]["anyOf"]
        }
        self.assertEqual(command_types, {"row.create"})

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.build_submit_plan_tool(
                command_types={
                    "sample.place",
                    "clip.adjust_pitch_semitones",
                },
                resource_refs_enabled=True,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_command_surface_empty")

    def test_generated_midi_clip_supports_every_typed_midi_consumer(self) -> None:
        context = self._core_context()
        context["clips"] = []
        context["rows"][0].update(
            {"mix_processing_supported": False, "has_usable_signal": False}
        )
        surfaces = [v3_server_contract.extract_capability_surface(context)]
        context_with_unrelated_clip = self._core_context()
        surfaces.append(
            v3_server_contract.extract_capability_surface(
                context_with_unrelated_clip
            )
        )
        note = {
            "pitch": 60,
            "start_beat": 0,
            "length_beats": 1,
            "velocity": 0.8,
        }
        consumers = {
            "midi.replace_notes": {"notes": [note]},
            "midi.append_notes": {"notes": [note]},
            "midi.chop_notes": {
                "subdivision": 8,
                "range": None,
                "velocity_decay_per_slice": 0.1,
            },
            "midi.transpose": {"semitones": 2},
        }

        for surface in surfaces:
            for command_type, extra_arguments in consumers.items():
                with self.subTest(
                    existing_clip_count=len(surface.clips),
                    command_type=command_type,
                ):
                    plan = {
                        "schema_version": "plan_v3_prototype_2",
                        "outcome": "plan",
                        "user_message": "Created and edited the MIDI part.",
                        "commands": [
                            {
                                "command_id": "create-midi",
                                "type": "midi.create_clip",
                                "arguments": {
                                    "destination": {"row_id": 101},
                                    "start_beat": 0,
                                    "length_beats": 4,
                                    "notes": [note],
                                },
                            },
                            {
                                "command_id": "edit-midi",
                                "type": command_type,
                                "arguments": {
                                    "clip_ref": {
                                        "command_id": "create-midi",
                                        "output": "midi_clip",
                                    },
                                    **extra_arguments,
                                },
                            },
                        ],
                        "question_options": [],
                    }
                    validated = v3_server_contract.parse_and_validate_provider_plan(
                        self._provider_payload(plan),
                        command_types={"midi.create_clip", command_type},
                        resource_refs_enabled=True,
                        capability_surface=surface,
                    )
                    self.assertEqual(validated, plan)

    def test_generated_midi_clip_uses_generated_row_instrument(self) -> None:
        context = self._core_context()
        context["clips"] = []
        surface = v3_server_contract.extract_capability_surface(context)
        note = {
            "pitch": 60,
            "start_beat": 0,
            "length_beats": 1,
            "velocity": 0.8,
        }
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Created and transposed a MIDI part.",
            "commands": [
                {
                    "command_id": "create-row",
                    "type": "row.create",
                    "arguments": {
                        "name": "New Piano",
                        "lane": {
                            "kind": "midi",
                            "instrument_id": "free-piano",
                        },
                        "position": {"kind": "end"},
                    },
                },
                {
                    "command_id": "create-midi",
                    "type": "midi.create_clip",
                    "arguments": {
                        "destination": {
                            "row_ref": {
                                "command_id": "create-row",
                                "output": "row",
                            }
                        },
                        "start_beat": 0,
                        "length_beats": 4,
                        "notes": [note],
                    },
                },
                {
                    "command_id": "transpose",
                    "type": "midi.transpose",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "create-midi",
                            "output": "midi_clip",
                        },
                        "semitones": 2,
                    },
                },
            ],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"row.create", "midi.create_clip", "midi.transpose"},
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        self.assertEqual(validated, plan)

    def test_converted_midi_clip_supports_typed_midi_consumer(self) -> None:
        context = self._core_context()
        context["rows"][0].update(
            {"lane_kind": "audio", "instrument_id": ""}
        )
        context["clips"] = [
            {
                "clip_id": "audio-source",
                "row_id": 101,
                "kind": "audio",
                "length_beats": 8,
            }
        ]
        surface = v3_server_contract.extract_capability_surface(context)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Converted and transposed the clip.",
            "commands": [
                {
                    "command_id": "convert",
                    "type": "clip.convert_to_midi",
                    "arguments": {
                        "clip_id": "audio-source",
                        "instrument_id": "free-piano",
                    },
                },
                {
                    "command_id": "transpose",
                    "type": "midi.transpose",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "convert",
                            "output": "midi_clip",
                        },
                        "semitones": 2,
                    },
                },
            ],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"clip.convert_to_midi", "midi.transpose"},
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        self.assertEqual(validated, plan)

    def test_created_midi_clip_matches_client_arrangement_limits(self) -> None:
        for refs in (False, True):
            for beats_per_bar in (None, 3, 4, 6):
                limit = (beats_per_bar or 4) * 8
                cases = [
                    (limit, limit - 1, 1, None),
                    (limit + 1, 0, 1, "v3_plan_midi_arrangement_limit"),
                    (4, 3.5, 1, "v3_plan_midi_note_out_of_bounds"),
                    (4, 3.0, 1.0000001, "v3_plan_midi_note_out_of_bounds"),
                ]
                for length, note_start, note_length, error in cases:
                    with self.subTest(refs=refs, meter=beats_per_bar, length=length, error=error):
                        context = self._core_context()
                        if beats_per_bar is not None:
                            context["project"]["beats_per_bar"] = beats_per_bar
                        plan = {
                            "schema_version": "plan_v3_prototype_2",
                            "outcome": "plan",
                            "user_message": "Created the MIDI part.",
                            "question_options": [],
                            "commands": [{
                                "command_id": "create-midi",
                                "type": "midi.create_clip",
                                "arguments": {
                                    "destination": {"row_id": 101},
                                    "start_beat": 128,
                                    "length_beats": length,
                                    "notes": [{"pitch": 60, "start_beat": note_start,
                                               "length_beats": note_length, "velocity": 0.8}],
                                },
                            }],
                        }
                        def validate():
                            return v3_server_contract.parse_and_validate_provider_plan(
                                self._provider_payload(plan), command_types={"midi.create_clip"},
                                resource_refs_enabled=refs,
                                capability_surface=v3_server_contract.extract_capability_surface(context),
                            )
                        if error is None:
                            self.assertEqual(validate(), plan)
                        else:
                            with self.assertRaises(v3_server_contract.V3ContractError) as caught:
                                validate()
                            self.assertEqual(caught.exception.code, error)

    def test_midi_creation_meter_is_validated_and_fingerprinted(self) -> None:
        for meter in (True, "4", 0, -1, float("nan"), float("inf"), 10 ** 400):
            with self.subTest(meter=str(meter)):
                context = self._core_context()
                context["project"]["beats_per_bar"] = meter
                with self.assertRaises(v3_server_contract.V3ContractError) as caught:
                    v3_server_contract.extract_capability_surface(context)
                self.assertEqual(caught.exception.code, "v3_capability_context_invalid")
        fingerprints = []
        for meter in (3, 4):
            context = self._core_context()
            context["project"]["beats_per_bar"] = meter
            fingerprints.append(v3_server_contract.contract_fingerprint(
                command_types={"midi.create_clip"}, resource_refs_enabled=True,
                capability_surface=v3_server_contract.extract_capability_surface(context),
            ))
        self.assertNotEqual(*fingerprints)

    def test_generated_midi_clip_preserves_note_validation(self) -> None:
        context = self._core_context()
        context["clips"] = []
        surface = v3_server_contract.extract_capability_surface(context)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Replaced the MIDI notes.",
            "commands": [
                {
                    "command_id": "create-midi",
                    "type": "midi.create_clip",
                    "arguments": {
                        "destination": {"row_id": 101},
                        "start_beat": 0,
                        "length_beats": 4,
                        "notes": [
                            {
                                "pitch": 60,
                                "start_beat": 0,
                                "length_beats": 1,
                                "velocity": 0.8,
                            }
                        ],
                    },
                },
                {
                    "command_id": "replace-midi",
                    "type": "midi.replace_notes",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "create-midi",
                            "output": "midi_clip",
                        },
                        "notes": [
                            {
                                "pitch": 60,
                                "start_beat": 3.5,
                                "length_beats": 1,
                                "velocity": 0.8,
                            }
                        ],
                    },
                },
            ],
            "question_options": [],
        }

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(plan),
                command_types={"midi.create_clip", "midi.replace_notes"},
                resource_refs_enabled=True,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_midi_note_out_of_bounds")

    def test_generated_audio_clip_supports_typed_audio_consumer(self) -> None:
        context = self._core_context()
        context["rows"][0].update(
            {
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": False,
                "has_usable_signal": False,
            }
        )
        context["clips"] = []
        surface = v3_server_contract.extract_capability_surface(context)
        plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Placed and tuned the sample.",
            "commands": [
                {
                    "command_id": "place",
                    "type": "sample.place",
                    "arguments": {
                        "destination": {"row_id": 101},
                        "placements": [
                            {"asset_id": "asset-1", "start_beat": 0}
                        ],
                    },
                },
                {
                    "command_id": "pitch",
                    "type": "clip.adjust_pitch_semitones",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "place",
                            "output": "audio_clip",
                        },
                        "delta_semitones": -2,
                    },
                },
            ],
            "question_options": [],
        }

        validated = v3_server_contract.parse_and_validate_provider_plan(
            self._provider_payload(plan),
            command_types={"sample.place", "clip.adjust_pitch_semitones"},
            resource_refs_enabled=True,
            capability_surface=surface,
        )
        self.assertEqual(validated, plan)

    def test_generated_clip_rejects_wrong_kind_and_deleted_reference(self) -> None:
        context = self._core_context()
        context["rows"][0].update(
            {
                "lane_kind": "audio",
                "instrument_id": "",
                "mix_processing_supported": False,
                "has_usable_signal": False,
            }
        )
        context["project"]["row_capacity"]["current_rows"] = 2
        context["rows"].append(
            {
                "row_id": 102,
                "lane_kind": "instrument",
                "instrument_id": "free-piano",
                "mix_processing_supported": True,
                "has_usable_signal": True,
                "effects": [],
            }
        )
        context["clips"] = [
            {
                "clip_id": "existing-midi",
                "row_id": 102,
                "kind": "midi",
                "instrument_id": "free-piano",
                "length_beats": 4,
                "midi_notes": [],
            }
        ]
        surface = v3_server_contract.extract_capability_surface(context)
        place = {
            "command_id": "place",
            "type": "sample.place",
            "arguments": {
                "destination": {"row_id": 101},
                "placements": [{"asset_id": "asset-1", "start_beat": 0}],
            },
        }
        duplicate = {
            "command_id": "duplicate",
            "type": "clip.duplicate_to",
            "arguments": {
                "clip_ref": {"command_id": "place", "output": "audio_clip"},
                "destination_row_id": 101,
                "start_beat": 4,
            },
        }
        wrong_kind_plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Edited the clip.",
            "commands": [
                place,
                duplicate,
                {
                    "command_id": "transpose",
                    "type": "midi.transpose",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "duplicate",
                            "output": "copy_clip",
                        },
                        "semitones": 2,
                    },
                },
            ],
            "question_options": [],
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(wrong_kind_plan),
                command_types={
                    "sample.place",
                    "clip.duplicate_to",
                    "midi.transpose",
                },
                resource_refs_enabled=True,
                capability_surface=surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_target_type_invalid")

        midi_context = self._core_context()
        midi_context["clips"] = []
        midi_surface = v3_server_contract.extract_capability_surface(midi_context)
        note = {
            "pitch": 60,
            "start_beat": 0,
            "length_beats": 1,
            "velocity": 0.8,
        }
        deleted_plan = {
            "schema_version": "plan_v3_prototype_2",
            "outcome": "plan",
            "user_message": "Edited the clip.",
            "commands": [
                {
                    "command_id": "create-midi",
                    "type": "midi.create_clip",
                    "arguments": {
                        "destination": {"row_id": 101},
                        "start_beat": 0,
                        "length_beats": 4,
                        "notes": [note],
                    },
                },
                {
                    "command_id": "delete-midi",
                    "type": "clip.delete",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "create-midi",
                            "output": "midi_clip",
                        }
                    },
                },
                {
                    "command_id": "transpose",
                    "type": "midi.transpose",
                    "arguments": {
                        "clip_ref": {
                            "command_id": "create-midi",
                            "output": "midi_clip",
                        },
                        "semitones": 2,
                    },
                },
            ],
            "question_options": [],
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.parse_and_validate_provider_plan(
                self._provider_payload(deleted_plan),
                command_types={
                    "midi.create_clip",
                    "clip.delete",
                    "midi.transpose",
                },
                resource_refs_enabled=True,
                capability_surface=midi_surface,
            )
        self.assertEqual(raised.exception.code, "v3_plan_target_type_invalid")

    def test_runtime_mix_targets_do_not_embed_ready_resource_ids(self) -> None:
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

        self.assertNotIn("enum", direct_row["properties"]["row_id"])
        self.assertNotIn("enum", direct_group["properties"]["group_id"])

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

    def test_dissolved_stable_groups_are_unavailable_to_later_commands(self) -> None:
        surface = self._group_surface(members=[1, 2])
        invalid_sequences = [
            [
                {
                    "command_id": "remove-member",
                    "type": "group.remove_row",
                    "arguments": {"group_id": "group-1", "row_id": 2},
                },
                {
                    "command_id": "collapse",
                    "type": "group.set_collapsed",
                    "arguments": {"group_id": "group-1", "collapsed": True},
                },
            ],
            [
                {
                    "command_id": "delete-member",
                    "type": "row.delete",
                    "arguments": {"row_id": 2},
                },
                {
                    "command_id": "collapse",
                    "type": "group.set_collapsed",
                    "arguments": {"group_id": "group-1", "collapsed": True},
                },
            ],
            [
                {
                    "command_id": "replacement",
                    "type": "group.create",
                    "arguments": {"row_ids": [1, 3], "name": "Replacement"},
                },
                {
                    "command_id": "collapse-old",
                    "type": "group.set_collapsed",
                    "arguments": {"group_id": "group-1", "collapsed": True},
                },
            ],
        ]

        for commands in invalid_sequences:
            with self.subTest(first_command=commands[0]["type"]):
                with self.assertRaises(
                    v3_server_contract.V3ContractError
                ) as raised:
                    v3_server_contract.validate_plan_capabilities(
                        {"commands": commands}, surface
                    )
                self.assertEqual(
                    raised.exception.code, "v3_plan_capability_invalid"
                )

    def test_dissolved_generated_group_reference_is_retired(self) -> None:
        group_ref = {"command_id": "create-group", "output": "group"}
        commands = [
            {
                "command_id": "create-group",
                "type": "group.create",
                "arguments": {
                    "members": [{"row_id": 1}, {"row_id": 2}],
                    "name": "Pair",
                },
            },
            {
                "command_id": "remove-member",
                "type": "group.remove_row",
                "arguments": {"group_ref": group_ref, "row_id": 2},
            },
            {
                "command_id": "collapse",
                "type": "group.set_collapsed",
                "arguments": {"group_ref": group_ref, "collapsed": True},
            },
        ]

        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": commands}, self._group_surface()
            )
        self.assertEqual(raised.exception.code, "v3_plan_resource_ref_invalid")

    def test_surviving_group_uses_only_its_current_members(self) -> None:
        commands = [
            {
                "command_id": "remove-member",
                "type": "group.remove_row",
                "arguments": {"group_id": "group-1", "row_id": 1},
            },
            {
                "command_id": "collapse",
                "type": "group.set_collapsed",
                "arguments": {"group_id": "group-1", "collapsed": True},
            },
        ]
        validated = v3_server_contract.validate_plan_capabilities(
            {"commands": commands}, self._group_surface(members=[1, 2, 3])
        )
        self.assertEqual(validated["row_count"], 4)

        mix = self._mix_plan("reverb")["commands"][0]
        mix["arguments"]["target"] = {
            "scope": "group",
            "group_id": "group-1",
        }
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {"commands": [commands[0], mix]},
                self._group_surface(members=[1, 2, 3], ready_rows={1}),
            )
        self.assertEqual(raised.exception.code, "v3_plan_capability_invalid")

    def test_group_remove_requires_current_membership(self) -> None:
        with self.assertRaises(v3_server_contract.V3ContractError) as raised:
            v3_server_contract.validate_plan_capabilities(
                {
                    "commands": [
                        {
                            "command_id": "remove-non-member",
                            "type": "group.remove_row",
                            "arguments": {
                                "group_id": "group-1",
                                "row_id": 4,
                            },
                        }
                    ]
                },
                self._group_surface(members=[1, 2, 3]),
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
