"""Synthetic-only tests. No provider, project, or production access."""
import copy
import json
import os
from pathlib import Path
import socket
import sys
import statistics
import time
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest import mock

import test_api_responses as handler_tests

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool/ai_v3_eval"))
import bounded_pitch_repair as repair
from common import v3_server_contract as contract
from common.llm_contract import build_openai_responses_request
from handlers import api_responses


def fixture():
    helper = handler_tests.ApiResponsesTests()
    body = helper._v3_midi_repair_body()
    body.update(original_request="Create two contrasting 8-bar sections",
                supported_command_types=sorted(contract.SERVER_COMMAND_TYPES),
                resource_refs_enabled=True,
                conversation=[
                    {"role": "user", "content": "electric guitar heavy metal 16 bars suoper rich chord prog"},
                    {"role": "assistant", "content": "Would you like one 8-bar section or two contrasting 8-bar sections?"}])
    core = body["core_context"]
    core["project"].update(bpm=108, beats_per_bar=4)
    core["rows"][0]["instrument_id"] = "guitar"
    core["clips"][0].update(instrument_id="guitar", length_beats=32)
    core["instruments"] = ["guitar", "wide"]
    core["instrument_catalog"] = [
        {"instrument_id": "guitar", "name": "Electric Guitar",
         "playable_pitch_ranges": [{"low": 40, "high": 86}]},
        {"instrument_id": "wide", "name": "Unrestricted", "playable_pitch_ranges": []}]
    plan = helper._v3_midi_repair_plan(out_of_bounds=False)
    plan["user_message"] = "Rebuilt both sections while preserving the instrument."
    plan["commands"] = [create("first", 0, [36, 38, 60]), create("second", 32, [35, 37, 64])]
    return body, plan


def note(pitch, start=0):
    return {"pitch": pitch, "start_beat": start, "length_beats": 1, "velocity": 0.8}


def create(command_id, start, pitches):
    return {"command_id": command_id, "type": "midi.create_clip", "arguments": {
        "destination": {"row_id": 101}, "start_beat": start,
        "length_beats": 32, "notes": [note(p, i) for i, p in enumerate(pitches)]}}


def validated(body):
    request = contract.validate_context_request(body, raw_body_bytes=repair.size(body))
    provider_body = contract.build_provider_request(request, model="gpt-5.6-luna",
        reasoning_effort="low", max_output_tokens=8192)
    return request, provider_body


def patch_payload(values):
    return {"status": "completed", "output": [{"type": "function_call",
        "name": repair.TOOL_NAME, "arguments": repair.canonical(values)}]}


def mocked_patch(case):
    # Explicit synthetic model output, not a runtime correction algorithm.
    return patch_payload({f"c{v['command_index']}_n{v['note_index']}": 48
                          for v in case.violations})


def comparison_report(reverse=False):
    """Repeatable aggregate comparison, with no request identifiers or text."""
    rows, rejected = [], {}
    variants = list(range(5))
    if reverse:
        variants.reverse()
    for variant in variants:
        body, plan = fixture()
        if variant in {1, 2}:
            plan["commands"] = [{"command_id": "notes", "type": (
                "midi.replace_notes" if variant == 1 else "midi.append_notes"),
                "arguments": {"clip_id": "drum-clip", "notes": [note(35), note(60), note(37)]}}]
        elif variant == 3:
            plan["commands"][1]["arguments"]["notes"][0]["start_beat"] = 40
        elif variant == 4:
            plan["commands"].append({"command_id": "transpose", "type": "midi.transpose",
                "arguments": {"clip_id": "drum-clip", "semitones": 12}})
        request, provider_body = validated(body)
        try:
            case = repair.prepare(request, repair.plan_payload(plan), provider_body)
        except repair.RepairRejected as error:
            rejected[error.code] = rejected.get(error.code, 0) + 1
            continue
        details = {k: v for k, v in case.violations[0].items()
                   if k not in {"note_index", "original_pitch"}}
        full_body = api_responses._v3_semantic_repair_request_body(
            provider_body, "v3_plan_midi_pitch_unavailable", details)
        rows.append(repair.comparison_metrics(case, full_body, mocked_patch(case)))
    rows.sort(key=repair.canonical)
    return {"synthetic_cases": len(variants), "accepted_mocked_repairs": len(rows),
            "rejected_cases": sum(rejected.values()), "rejection_categories": rejected,
            "comparisons": rows, "live_calls": 0, "provider_latency_measured": False}


def timing_report():
    """Informational local timings only, deliberately outside deterministic gates."""
    body, plan = fixture()
    request, provider_body = validated(body)
    timings = {"analysis_and_build_ms": [], "patch_and_full_validation_ms": []}
    for _ in range(20):
        start = time.perf_counter()
        case = repair.prepare(request, repair.plan_payload(plan), provider_body)
        timings["analysis_and_build_ms"].append((time.perf_counter() - start) * 1000)
        start = time.perf_counter()
        repair.reconstruct(case, mocked_patch(case))
        timings["patch_and_full_validation_ms"].append((time.perf_counter() - start) * 1000)
    return {"iterations": 20, "provider_latency_measured": False,
            "local_timings": {key: {"median": round(statistics.median(values), 3),
                "p95": round(sorted(values)[18], 3)} for key, values in timings.items()}}


class OfflineAdapter:
    """Test-only provider for the real handler's existing single repair call."""
    name = "offline-pitch-prototype"

    def __init__(self, request, initial, result=None):
        self.request, self.initial, self.result = request, initial, result
        self.bodies, self.timeouts, self.repair_bodies = [], [], []

    def forward_request(self, *, api_key, request_body, timeout_seconds):
        self.bodies.append(copy.deepcopy(request_body))
        self.timeouts.append(timeout_seconds)
        if len(self.bodies) > 2:
            raise AssertionError("Extra repair attempt")
        payload = self.initial
        if len(self.bodies) == 2:
            case = repair.prepare(self.request, self.initial, self.bodies[0])
            self.repair_bodies.append(case.body)
            if isinstance(self.result, Exception):
                raise self.result
            payload = self.result or mocked_patch(case)
        return {"statusCode": 200, "body": json.dumps(payload)}


class BoundedPitchRepairTests(unittest.TestCase):
    def setUp(self):
        self.no_network = mock.patch.object(socket, "create_connection",
            side_effect=AssertionError("Network forbidden"))
        self.no_network.start()
        self.addCleanup(self.no_network.stop)
        self.body, self.plan = fixture()

    def prepare(self):
        request, body = validated(self.body)
        return repair.prepare(request, repair.plan_payload(self.plan), body)

    def test_two_sections_patch_only_invalid_pitches(self):
        before = copy.deepcopy(self.plan)
        case = self.prepare()
        result = repair.reconstruct(case, mocked_patch(case))
        self.assertEqual(len(case.violations), 4)
        for c in range(2):
            for n in range(2):
                before["commands"][c]["arguments"]["notes"][n]["pitch"] = 48
        self.assertEqual(result, before)
        self.assertEqual(case.plan, self.plan)
        self.assertEqual([c["arguments"]["start_beat"] for c in result["commands"]], [0, 32])
        with self.assertRaises(contract.V3ContractError):
            contract.parse_and_validate_provider_plan(repair.plan_payload(self.plan),
                **repair.validation_args(case.request))

    def test_replace_append_and_valid_unrelated_mix_preserved(self):
        helper = handler_tests.ApiResponsesTests()
        self.plan = helper._v3_midi_repair_plan(out_of_bounds=False)
        self.plan["commands"][0]["arguments"]["notes"] = [note(35), note(60)]
        self.plan["commands"].insert(1, {"command_id": "append", "type": "midi.append_notes",
            "arguments": {"clip_id": "drum-clip", "notes": [note(37)]}})
        case = self.prepare()
        result = repair.reconstruct(case, mocked_patch(case))
        self.assertEqual(result["commands"][-1], self.plan["commands"][-1])
        self.assertEqual(len(case.violations), 2)

    def test_range_endpoints_gaps_drums_and_unrestricted(self):
        for ranges, valid, invalid in [([(40, 86)], [40, 86], [39, 87]),
                                       ([(35, 38), (42, 42)], [35, 38, 42], [39, 41])]:
            with self.subTest(ranges=ranges):
                self.body["core_context"]["instrument_catalog"][0]["playable_pitch_ranges"] = [
                    {"low": a, "high": b} for a, b in ranges]
                self.plan["commands"] = [create("create", 0, invalid + valid)]
                case = self.prepare()
                for pitch in valid + invalid:
                    values = {f"c0_n{i}": pitch for i in range(len(invalid))}
                    if pitch in valid:
                        repair.reconstruct(case, patch_payload(values))
                    else:
                        with self.assertRaises(repair.RepairRejected):
                            repair.reconstruct(case, patch_payload(values))
        self.body["core_context"]["instrument_catalog"][0]["playable_pitch_ranges"] = []
        with self.assertRaisesRegex(repair.RepairRejected, "no_pitch_violations"):
            self.prepare()

    def test_preceding_switch_and_generated_references(self):
        self.body["core_context"]["rows"][0]["instrument_id"] = "wide"
        self.body["core_context"]["clips"][0]["instrument_id"] = "wide"
        self.plan["commands"].insert(0, {"command_id": "switch", "type": "row.set_instrument",
            "arguments": {"row_id": 101, "instrument_id": "guitar"}})
        case = self.prepare()
        self.assertEqual({v["effective_instrument_id"] for v in case.violations}, {"guitar"})
        repair.reconstruct(case, mocked_patch(case))
        self.plan["commands"] = [{"command_id": "new-row", "type": "row.create", "arguments": {
            "name": "Guitar", "lane": {"kind": "midi", "instrument_id": "guitar"},
            "position": {"kind": "end"}}}, create("new-clip", 0, [35]),
            {"command_id": "replace", "type": "midi.replace_notes", "arguments": {
                "clip_ref": {"command_id": "new-clip", "output": "midi_clip"},
                "notes": [note(37)]}}]
        self.plan["commands"][1]["arguments"]["destination"] = {
            "row_ref": {"command_id": "new-row", "output": "row"}}
        case = self.prepare()
        repair.reconstruct(case, mocked_patch(case))
        self.assertEqual(len(case.violations), 2)

    def test_downstream_dependencies_are_not_solved(self):
        for command in [
            {"command_id": "later", "type": "row.set_instrument", "arguments": {
                "row_id": 101, "instrument_id": "wide"}},
            {"command_id": "later", "type": "midi.transpose", "arguments": {
                "clip_id": "drum-clip", "semitones": 12}}]:
            with self.subTest(command=command["type"]):
                self.plan["commands"] = [create("first", 0, [36]), command]
                with self.assertRaisesRegex(repair.RepairRejected, "dependency_unsupported"):
                    self.prepare()

    def test_boundaries_are_still_validated_after_pitch_failure(self):
        self.plan["commands"] = [{"command_id": "replace", "type": "midi.replace_notes",
            "arguments": {"clip_id": "drum-clip", "notes": [note(35, 31)]}}]
        self.body["core_context"]["clips"][0]["length_beats"] = 31.9986
        with self.assertRaisesRegex(repair.RepairRejected, "note_out_of_bounds"):
            self.prepare()
        self.body["core_context"]["project"]["midi_boundary_policy"] = "extend_1ms_v1"
        case = self.prepare()
        repair.reconstruct(case, mocked_patch(case))
        self.body["core_context"]["clips"][0]["length_beats"] = 31.99
        with self.assertRaisesRegex(repair.RepairRejected, "note_out_of_bounds"):
            self.prepare()

    def test_structure_and_non_pitch_failures_refuse_analysis(self):
        for change in (lambda p: p.update(extra=True),
                       lambda p: p["commands"][1]["arguments"].update(length_beats=64),
                       lambda p: p["commands"][1].update(command_id="first")):
            self.body, self.plan = fixture()
            change(self.plan)
            with self.assertRaises(repair.RepairRejected):
                self.prepare()

    def test_malformed_patch_refusal_and_incomplete_rejected(self):
        case = self.prepare()
        values = {f"c{v['command_index']}_n{v['note_index']}": 48 for v in case.violations}
        wrong = [None, {}, {"status": "failed"},
                 {"status": "incomplete", "output": []},
                 {"output": [{"type": "refusal"}]},
                 {"output": [{"type": "message", "content": [{"type": "refusal"}]}]},
                 patch_payload({}), patch_payload(dict(values, extra=60))]
        for value in (True, 48.5, "48", -1, 128, 38, None):
            changed = dict(values, c0_n0=value)
            wrong.append(patch_payload(changed))
        duplicate = patch_payload(values)
        duplicate["output"][0]["arguments"] = '{"c0_n0":48,"c0_n0":60}'
        wrong.append(duplicate)
        oversized = patch_payload(values)
        oversized["output"][0]["arguments"] = "x" * 24_001
        wrong.append(oversized)
        nested = patch_payload(values)
        nested["output"][0]["arguments"] = "[" * 2000 + "0" + "]" * 2000
        wrong.append(nested)
        repeated_call = patch_payload(values)
        repeated_call["output"] *= 2
        wrong.append(repeated_call)
        wrong_tool = patch_payload(values)
        wrong_tool["output"][0]["name"] = "submit_plan_v3"
        wrong.append(wrong_tool)
        for payload in wrong:
            with self.subTest(payload_type=type(payload).__name__):
                with self.assertRaises(repair.RepairRejected):
                    repair.reconstruct(case, payload)

    def test_settings_and_initial_body_unchanged_and_no_catalog(self):
        request, original = validated(self.body)
        snapshot = copy.deepcopy(original)
        case = repair.prepare(request, repair.plan_payload(self.plan), original)
        self.assertEqual(original, snapshot)
        for key in original.keys() - {"tools", "tool_choice", "messages", "instructions"}:
            self.assertEqual(case.body[key], original[key])
        text = repair.canonical(case.body)
        self.assertNotIn('"instrument_catalog"', text)
        self.assertNotIn('"library_assets"', text)
        self.assertNotIn('"wide"', text)
        upstream = build_openai_responses_request(case.body)
        self.assertTrue(upstream["tools"][0]["strict"])
        self.assertEqual(upstream["tool_choice"]["name"], repair.TOOL_NAME)

    def test_limits_and_secrets_do_not_leak(self):
        request, body = validated(self.body)
        marker = "UNIQUE_PRIVATE_TEST_MARKER"
        request["original_request"] = marker * 12_000
        output = StringIO()
        with redirect_stdout(output), self.assertRaises(repair.RepairRejected) as caught:
            repair.prepare(request, repair.plan_payload(self.plan), body)
        self.assertNotIn(marker, str(caught.exception) + output.getvalue())
        case = self.prepare()
        request, body = validated(self.body)
        with mock.patch.object(contract, "MAX_RUNTIME_TOOL_BYTES", 1):
            with self.assertRaises(repair.RepairRejected):
                repair.prepare(request, repair.plan_payload(self.plan), body)
        with mock.patch.object(contract, "MAX_REQUEST_BYTES", repair.size(case.body) - 1):
            with self.assertRaises(repair.RepairRejected):
                repair.prepare(request, repair.plan_payload(self.plan), body)

    def test_final_validation_catches_state_or_plan_corruption(self):
        case = self.prepare()
        context = copy.deepcopy(self.body["core_context"])
        context.update(rows=[], clips=[])
        context["project"]["row_capacity"]["current_rows"] = 0
        case.request["capability_surface"] = contract.extract_capability_surface(context)
        with self.assertRaises(repair.RepairRejected):
            repair.reconstruct(case, mocked_patch(case))

    def test_report_is_deterministic_and_privacy_safe(self):
        first, second = comparison_report(), comparison_report(reverse=True)
        self.assertEqual(repair.canonical(first), repair.canonical(second))
        self.assertEqual(first["accepted_mocked_repairs"], 3)
        self.assertEqual(first["rejected_cases"], 2)
        for row in first["comparisons"]:
            self.assertLess(row["targeted_repair_request_bytes"], row["full_repair_request_bytes"])
            self.assertLess(row["patch_output_bytes"], row["full_plan_output_bytes"])
        marker = "A uniquely private synthetic melody"
        self.body["original_request"] = marker
        self.body["conversation"] = [{"role": "user", "content": marker}]
        self.body["project_id"] = marker
        self.body["core_context"]["project"]["name"] = marker
        self.plan["user_message"] = "Created " + marker + "."
        self.plan["commands"][0]["command_id"] = "private-command-marker"
        case = self.prepare()
        output = StringIO()
        with redirect_stdout(output):
            metrics = repair.comparison_metrics(case, case.body, mocked_patch(case))
        self.assertNotIn(marker, repair.canonical(metrics) + output.getvalue())

    def test_unknown_instrument_and_transpose_only_failure_not_patched(self):
        from dataclasses import replace
        request, provider_body = validated(self.body)
        self.plan["commands"] = [{"command_id": "notes", "type": "midi.replace_notes",
            "arguments": {"clip_id": "drum-clip", "notes": [note(35)]}}]
        surface = request["capability_surface"]
        request["capability_surface"] = replace(surface, clips=tuple(
            replace(clip, instrument_id="") for clip in surface.clips))
        with self.assertRaisesRegex(repair.RepairRejected, "instrument_unknown"):
            repair.prepare(request, repair.plan_payload(self.plan), provider_body)
        self.body["core_context"]["clips"][0]["midi_notes"] = [note(40)]
        self.plan["commands"] = [{"command_id": "transpose", "type": "midi.transpose",
            "arguments": {"clip_id": "drum-clip", "semitones": -12}}]
        with self.assertRaises(repair.RepairRejected):
            self.prepare()

    def test_actual_handler_deadline_attempts_and_settlement(self):
        for mode, status, attempts, success in [
            ("success", 200, 2, True), ("invalid", 502, 2, False),
            ("timeout", 504, 2, False), ("exhausted", 502, 1, False),
            ("valid", 200, 1, True), ("long", 200, 2, True)]:
            with self.subTest(mode=mode):
                helper = handler_tests.ApiResponsesTests()
                helper.setUp()
                try:
                    body, plan = fixture()
                    request, provider_body = validated(body)
                    if mode == "valid":
                        case = repair.prepare(request, repair.plan_payload(plan), provider_body)
                        plan = repair.reconstruct(case, mocked_patch(case))
                    result = (TimeoutError("synthetic timeout") if mode == "timeout" else
                              patch_payload({}) if mode == "invalid" else None)
                    provider = OfflineAdapter(request, repair.plan_payload(plan), result)
                    with mock.patch.dict(os.environ, {"AI_V3_ENABLED": "true",
                        "AI_V3_SERVER_CONTRACT_ENABLED": "true",
                        "LLM_PROVIDER": "openai",
                        "AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS": "105" if mode == "long" else "27",
                        "AI_V3_TIMEOUT_SECONDS": "105" if mode == "long" else "27"}), mock.patch.object(
                        api_responses, "_load_api_key", return_value="synthetic"), mock.patch.object(
                        api_responses, "get_provider", return_value=provider), mock.patch.object(
                        api_responses.time, "monotonic", side_effect=(
                            [100., 200.] if mode == "exhausted" else [100., 110., 110.]
                        )), redirect_stdout(StringIO()):
                        response = api_responses.handler(handler_tests._authed_event(
                            json.dumps(body), path="/v1/llm/v3/responses"),
                            handler_tests._LambdaContext(115_000 if mode == "long" else 30_000))
                    self.assertEqual(response["statusCode"], status)
                    self.assertEqual(len(provider.bodies), attempts)
                    self.assertEqual(len(helper.fake_usage_repo.reserve_calls), 1)
                    self.assertEqual(len(helper.fake_usage_repo.finalize_calls), int(success))
                    self.assertEqual(len(helper.fake_usage_repo.release_calls), int(not success))
                    if attempts == 2:
                        self.assertEqual(provider.timeouts, [105, 95] if mode == "long" else [27, 17])
                finally:
                    helper.doCleanups()


if __name__ == "__main__":
    if sys.argv[1:] in (["--report"], ["--timing"]):
        with mock.patch.object(socket, "create_connection", side_effect=AssertionError("Network forbidden")):
            print(repair.canonical(timing_report() if sys.argv[1] == "--timing" else comparison_report()))
    else:
        unittest.main()
