from __future__ import annotations

import copy
import unittest
import json
import tempfile
from pathlib import Path

from test_producer_capture_converter import _bundle
from producer_capture_converter import convert_bundle, _sha256, _split, run
from train_mix_refine_models import load_objective
from evaluate_producer_models import evaluate
from common.mix_plugin_contract import extra_features, proposed_value
from common.mix_resolve import MixResolveService, _scale_action


def plugin_bundle(*, master=False, plugin="Compressor", parameter="Threshold", low=-60.0,
                  high=0.0, initial=-12.0, proposal=-24.0, final=-18.0):
    bundle = _bundle()
    episode = bundle["episodes"][0]
    effect = {"name": plugin, "effectId": plugin, "instanceId": "instance-17",
              "effectIndex": 0, "isBypassed": False,
              "parameters": [{"id": parameter, "name": parameter, "type": "float",
                              "value": initial, "min": low, "max": high, "unit": "dB", "interval": 0.01}]}
    action = {"type": "adjust_master_effect_param_by_name" if master else "adjust_effect_param_by_name",
              "data": {"effect_name_contains": plugin, "param_name": parameter, "mode": "set", "value": proposal}}
    if not master:
        action["data"]["row"] = 0
    before = episode["inference_traces"][0]["project_state"]
    if master:
        before["master_effects"] = [effect]
    else:
        before["rows"][0]["effects"] = [effect]
    after = copy.deepcopy(before)
    effects = after["master_effects"] if master else after["rows"][0]["effects"]
    effects[0]["parameters"][0]["value"] = final
    episode["state_before"]["project_state"] = copy.deepcopy(before)
    episode["state_after"]["project_state"] = after
    episode["inference_traces"][0]["actions"] = [action]
    episode["inference_traces"][0]["resolved_actions"] = [action]
    episode["actions_raw"] = [action]
    return bundle


class PluginTrainingTests(unittest.TestCase):
    def test_continuous_parameters_across_plugins_and_buses(self):
        for master in (False, True):
            for settings in ({}, {"plugin": "EQ Parametric", "parameter": "Band 1 Frequency",
                                  "low": 20, "high": 20000, "initial": 1000, "proposal": 3000, "final": 2000},
                                 {"plugin": "Reverb", "parameter": "Mix", "low": 0, "high": 1,
                                  "initial": 0.1, "proposal": 0.5, "final": 0.3}):
                with self.subTest(master=master, settings=settings):
                    row = convert_bundle(plugin_bundle(master=master, **settings))[0]
                    self.assertTrue(row["eligibility"]["mix_apply"], row["exclusion_reasons"])
                    self.assertAlmostEqual(row["labels"]["magnitude_scale"], 0.5)
                    self.assertEqual(len(row["plugin_feature_vector"]), 64)
                    self.assertEqual(row["final_plugin_target"]["instance_id"], "instance-17")

    def test_removed_replaced_duplicate_or_bypassed_plugins_are_excluded(self):
        for mutation in ("removed", "replaced", "duplicate", "bypassed", "range", "identity"):
            bundle = plugin_bundle()
            e = bundle["episodes"][0]
            before = e["inference_traces"][0]["project_state"]["rows"][0]["effects"]
            after = e["state_after"]["project_state"]["rows"][0]["effects"]
            if mutation == "removed": after.clear()
            if mutation == "replaced": after[0]["instanceId"] = "different-instance"
            if mutation == "duplicate": before.append(copy.deepcopy(before[0]))
            if mutation == "bypassed": after[0]["isBypassed"] = True
            if mutation == "range": after[0]["parameters"][0]["max"] = 10
            if mutation == "identity": before[0]["instanceId"] = ""
            row = convert_bundle(bundle)[0]
            self.assertFalse(row["eligibility"]["mix_apply"], mutation)
            self.assertFalse(row["eligibility"]["mix_magnitude"], mutation)

    def test_reorder_follows_instance_not_old_index(self):
        bundle = plugin_bundle()
        effects = bundle["episodes"][0]["state_after"]["project_state"]["rows"][0]["effects"]
        effects.insert(0, {"name": "Limiter", "effectId": "Limiter", "instanceId": "other"})
        row = convert_bundle(bundle)[0]
        self.assertEqual(row["final_plugin_target"]["chain_index_after"], 1)
        self.assertAlmostEqual(row["labels"]["magnitude_scale"], 0.5)

    def test_discrete_choice_is_apply_target_not_magnitude(self):
        bundle = plugin_bundle()
        e = bundle["episodes"][0]
        before = e["inference_traces"][0]["project_state"]
        after = e["state_after"]["project_state"]
        for project, value in ((before, "Soft"), (after, "Hard")):
            project["rows"][0]["effects"][0]["parameters"][0] = {
                "id": "Mode", "name": "Mode", "type": "choice", "value": value,
                "valueNormalized": 0 if value == "Soft" else 1, "choice_0": "Soft", "choice_1": "Hard"}
        action = e["inference_traces"][0]["actions"][0]
        action["data"].update(param_name="Mode", value=1.0)
        row = convert_bundle(bundle)[0]
        self.assertTrue(row["eligibility"]["mix_apply"], row["exclusion_reasons"])
        self.assertFalse(row["eligibility"]["mix_magnitude"])
        self.assertEqual(_scale_action(before, action, 0.2), action)
        after["rows"][0]["effects"][0]["parameters"][0]["value"] = "Soft"
        rejected = convert_bundle(bundle)[0]
        self.assertTrue(rejected["eligibility"]["mix_apply"])
        self.assertEqual(rejected["labels"]["apply"], 0)

    def test_normalized_values_clamps_and_quantization_follow_editor(self):
        parameter = {"type": "float", "value": -12, "min": -60, "max": 0, "interval": 0.1}
        self.assertAlmostEqual(proposed_value(parameter, {"mode": "set", "value_norm": 0.5, "value": -1}), -30)
        self.assertAlmostEqual(proposed_value(parameter, {"delta_norm": -0.1}), -18)
        self.assertEqual(proposed_value(parameter, {"mode": "set", "value": 20}), 0)
        self.assertAlmostEqual(proposed_value(parameter, {"mode": "set", "value": -18.04}), -18)
        self.assertEqual(proposed_value({"type": "bool", "value": False}, {"mode": "set", "value_norm": 0.7}), True)

    def test_insert_remove_reset_have_verified_structural_targets(self):
        for kind in ("ensure_effect", "delete_effect", "hard_reset_row_fx"):
            b = plugin_bundle(); e = b["episodes"][0]
            action = {"type": kind, "data": {"row": 0, "effect_name_contains": "Compressor"}}
            trace = e["inference_traces"][0]
            trace["actions"] = trace["resolved_actions"] = [action]
            if kind == "ensure_effect": trace["project_state"]["rows"][0]["effects"] = []
            else: e["state_after"]["project_state"]["rows"][0]["effects"] = []
            row = convert_bundle(b)[0]
            self.assertTrue(row["eligibility"]["mix_apply"], row["exclusion_reasons"])
            self.assertFalse(row["eligibility"]["mix_magnitude"])

    def test_features_distinguish_parameters_and_never_use_final_state(self):
        a = plugin_bundle(); b = plugin_bundle(final=-20)
        self.assertEqual(convert_bundle(a)[0]["plugin_feature_vector"], convert_bundle(b)[0]["plugin_feature_vector"])
        c = plugin_bundle(parameter="Attack")
        self.assertNotEqual(convert_bundle(a)[0]["plugin_feature_vector"], convert_bundle(c)[0]["plugin_feature_vector"])
        class Runner:
            vectors = []
            def feature_contract(self): return "mix_refine_plugins_v2"
            def predict_apply_score(self, x): self.vectors.append(x); return 0.9
            def predict_scalar(self, x): return 0.5
            def observability_context(self): return {}
        runner = Runner(); trace = a["episodes"][0]["inference_traces"][0]
        result = MixResolveService(runner=runner).resolve(project=trace["project_state"], goal=trace["goal"], actions=trace["actions"], strict=trace["strict"])
        self.assertFalse(result["fallback_used"])
        row = convert_bundle(a)[0]
        self.assertEqual(runner.vectors[0], row["feature_vector"] + row["plugin_feature_vector"])
        self.assertAlmostEqual(result["actions"][0]["data"]["value"], -18)

    def test_replay_compares_actual_runtime_output_with_current_model(self):
        class Runner:
            def __init__(self, scale): self.scale = scale
            def feature_contract(self): return "mix_refine_plugins_v2"
            def predict_apply_score(self, x): return 0.9
            def predict_scalar(self, x): return self.scale
            def observability_context(self): return {"scale": self.scale}
        bundle = plugin_bundle()
        bundle["project_ref"] = next(f"song-{i}" for i in range(10000) if _split(_sha256(f"song-{i}")) == "test")
        result = evaluate([bundle, bundle], candidate=Runner(0.5), baseline=Runner(1.0))
        self.assertEqual(result["examples"], 1)
        self.assertEqual(result["metrics"]["all/candidate/effective_scale_mae"]["mean"], 0)
        self.assertEqual(result["metrics"]["all/baseline/effective_scale_mae"]["mean"], 0.5)
        self.assertFalse(result["listening_quality_verified"])
        candidate = Runner(0.5)
        candidate.training_groups = {_sha256(bundle["project_ref"])}
        with self.assertRaisesRegex(ValueError, "used to train"):
            evaluate([bundle], candidate=candidate, baseline=Runner(1))

    def test_general_episode_archive_retains_non_model_plugin_edits(self):
        bundle = plugin_bundle()
        episode = bundle["episodes"][0]
        episode["inference_traces"] = []
        episode["actions_raw"] = [{"kind": "row_fx_bypass", "payload": {"row": 0, "index": 0, "bypassed": True}}]
        episode["producer_notes"] = "Bypassed while checking the arrangement"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); capture = root / "capture.json"
            capture.write_text(json.dumps(bundle))
            manifest = run([str(capture)], str(root / "dataset"))
            self.assertEqual(manifest["examples_written"], 0)
            self.assertEqual(manifest["episodes_archived"], 1)
            archive = root / "dataset" / manifest["episode_archive_shards"][0]["name"]
            saved = json.loads(archive.read_text())
            self.assertEqual(saved["episode"], episode)
            load_objective(root / "dataset", "mix_apply", plugins=True)
            archive.write_text("{}\n")
            with self.assertRaisesRegex(ValueError, "archive checksum"):
                load_objective(root / "dataset", "mix_apply", plugins=True)

    def test_group_bus_parameter_is_not_confused_with_individual_row_effect(self):
        bundle = plugin_bundle()
        episode = bundle["episodes"][0]
        for project in (episode["inference_traces"][0]["project_state"], episode["state_after"]["project_state"]):
            effects = project["rows"][0].pop("effects")
            project["rows"][0]["effects"] = []
            project["group_buses"] = [{"group_id": "vocals", "row_indices": [0], "effects": effects}]
        row = convert_bundle(bundle)[0]
        self.assertTrue(row["eligibility"]["mix_magnitude"], row["exclusion_reasons"])
        self.assertAlmostEqual(row["labels"]["magnitude_scale"], 0.5)
        trace = episode["inference_traces"][0]
        scaled = _scale_action(trace["project_state"], trace["actions"][0], 0.5, plugin_contract=True)
        self.assertAlmostEqual(scaled["data"]["value"], -18)
        trace["actions"][0]["data"]["force_individual_row"] = True
        self.assertFalse(convert_bundle(bundle)[0]["eligibility"]["mix_magnitude"])

    def test_structural_apply_decision_really_suppresses_even_with_strict_goal(self):
        class Runner:
            def feature_contract(self): return "mix_refine_plugins_v2"
            def predict_apply_score(self, x): return 0.1
            def predict_scalar(self, x): return 0.8
            def observability_context(self): return {}
        trace = plugin_bundle()["episodes"][0]["inference_traces"][0]
        response = MixResolveService(runner=Runner()).resolve(
            project=trace["project_state"], goal=trace["goal"], strict=True,
            actions=[{"type": "ensure_effect", "data": {"row": 0, "effect_name_contains": "Reverb"}}])
        self.assertFalse(response["fallback_used"])
        self.assertEqual(response["actions"], [])
        self.assertEqual(response["debug_entries"][0]["decision"], "drop_discrete")
