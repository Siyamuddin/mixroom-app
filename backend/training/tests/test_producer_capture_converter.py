from __future__ import annotations

import json
import copy
import math
import sys
import tempfile
import unittest
from pathlib import Path

TRAINING_ROOT = Path(__file__).resolve().parents[1]
if str(TRAINING_ROOT) not in sys.path:
    sys.path.insert(0, str(TRAINING_ROOT))

from producer_capture_converter import convert_bundle, run  # noqa: E402
from train_mix_refine_models import load_objective, ObjectiveRows, validate_readiness  # noqa: E402


def _project() -> dict:
    return {
        "bpm": 120.0,
        "max_rows": 1,
        "master_gain_0to3": 1.0,
        "master_pan_0to1": 0.5,
        "rows": [
            {
                "row": 0,
                "row_id": "stable-vocal-id",
                "hasAudio": True,
                "mix": {"gain_0to3": 1.0, "pan_0to1": 0.5},
                "features": {"approx_rms": 0.2, "approx_crest": 3.0},
                "audio_stats": {
                    "centroid_hz": 1000.0,
                    "integrated_lufs_est": -20.0,
                    "phase_corr": 0.8,
                },
                "role_probs": {"vocals": 0.9, "other": 0.1},
                "effects": [],
                "clips": [{"start_ms": 0.0, "end_ms": 12000.0}],
            }
        ],
    }


def _bundle() -> dict:
    return {
        "schema_version": "producer_training_capture_v4",
        "consent_version": "producer_training_2026_08_v1",
        "session_id": "session-test-1",
        "segmentation_version": "natural_action_burst_v2",
        "project_ref": "same-song",
        "episodes": [
            {
                "state_before": {"project_state": _project()},
                "state_after": {"project_state": {**_project(), "rows": [{**_project()["rows"][0], "mix": {"gain_0to3": 1.5, "pan_0to1": 0.5}}]}},
                "producer_outcome": "accepted",
                "inference_traces": [{
                    "mix_feature_contract_version": "mix_refine_v1",
                    "project_state": _project(),
                    "goal": {"intensity": 0.7, "execution_profile": "producer_safe", "intents": [{"kind": "gain"}]},
                    "strict": True,
                    "actions": [{"type": "set_row_gain", "data": {"row": 0, "mode": "set", "value": 2.0}}],
                    "resolved_actions": [{"type": "set_row_gain", "data": {"row": 0, "mode": "set", "value": 2.0}}],
                }],
                "request_or_context": {
                    "source": "ai_prompt",
                    "prompt": "Lower the vocal",
                },
                "actions_raw": [
                    {
                        "type": "set_row_gain",
                        "data": {"row": 0, "mode": "set", "value": 2.0},
                    },
                    {
                        "kind": "row_gain",
                        "payload": {
                            "row": 0,
                            "old_gain": 2.0,
                            "new_gain": 1.5,
                        },
                    },
                ],
                "status": "complete",
                "disposition": "idle_timeout",
                "diagnosis": "level_balance",
                "diagnoses": ["level_balance"],
                "strategies": ["target_level_change"],
                "provenance": {"label": "producer", "confidence": 1.0},
                "outcome_signals": {"survived_next_playback": True},
                "audio_target": {"status": "rendered"},
                "audio_feature_delta": {
                    "integrated_lufs": -1.2,
                    "phase_correlation": 0.02,
                },
            }
        ],
    }


class ProducerCaptureConverterTests(unittest.TestCase):
    def test_ai_correction_generates_exact_contract_and_scale(self) -> None:
        examples = convert_bundle(_bundle())
        self.assertEqual(len(examples), 2)
        ai = examples[0]
        manual = examples[1]
        self.assertEqual(len(ai["feature_vector"]), 77)
        self.assertEqual(ai["labels"]["apply"], 1)
        self.assertAlmostEqual(ai["labels"]["magnitude_scale"], 0.5)
        self.assertTrue(ai["eligibility"]["mix_magnitude"])
        self.assertIsNone(manual["labels"]["magnitude_scale"])
        self.assertFalse(manual["eligibility"]["mix_magnitude"])
        self.assertTrue(ai["eligibility"]["audio_result_delta"])

    def test_rejected_episode_produces_negative_apply_label(self) -> None:
        bundle = _bundle()
        episode = bundle["episodes"][0]
        episode["producer_outcome"] = "rejected"
        episode["actions_raw"] = episode["actions_raw"][:1]
        examples = convert_bundle(bundle)
        self.assertEqual(examples[0]["labels"]["apply"], 0)
        self.assertIsNone(examples[0]["labels"]["magnitude_scale"])
        self.assertTrue(examples[0]["eligibility"]["mix_apply"])
        self.assertEqual(examples[0]["sample_weight"], 1.0)

    def test_run_writes_deterministic_shards_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            input_path = root / "bundle.json"
            output_path = root / "output"
            input_path.write_text(json.dumps(_bundle()), encoding="utf-8")
            manifest = run([str(input_path)], str(output_path), shard_size=1)
            self.assertEqual(manifest["examples_written"], 2)
            self.assertEqual(len(manifest["shards"]), 2)
            self.assertEqual(manifest["feature_count"], 77)
            lines = []
            for shard in manifest["shards"]:
                lines.extend(
                    (output_path / shard["name"]).read_text(encoding="utf-8").splitlines()
                )
            self.assertEqual(len(lines), 2)
            self.assertEqual(len(json.loads(lines[0])["feature_vector"]), 77)
            apply = load_objective(output_path, "mix_apply")
            magnitude = load_objective(output_path, "mix_magnitude")
            self.assertEqual(len(apply.features), 1)
            self.assertEqual(len(magnitude.features), 1)
            self.assertAlmostEqual(magnitude.labels[0], 0.5)

    def test_questionnaire_taxonomy_and_playback_are_not_acceptance(self):
        bundle = _bundle()
        bundle["episodes"][0].pop("producer_outcome")
        row = convert_bundle(bundle)[0]
        self.assertIsNone(row["labels"]["apply"])
        self.assertFalse(row["eligibility"]["mix_apply"])

    def test_undo_redo_is_ambiguous_not_negative(self):
        bundle = _bundle()
        e = bundle["episodes"][0]
        e["status"] = "rejected"
        e["outcome_signals"] = {"rejected_by_undo": True, "restored_by_redo": True}
        row = convert_bundle(bundle)[0]
        self.assertIn("ambiguous_history_change", row["exclusion_reasons"]["mix_apply"])
        self.assertFalse(row["eligibility"]["mix_apply"])

    def test_exact_batch_features_match_online_inference(self):
        from common.mix_resolve import MixResolveService
        class Runner:
            def __init__(self): self.features = []
            def predict_apply_score(self, vector): self.features.append(vector); return 0.9
            def predict_scalar(self, vector): return 1.0
            def observability_context(self): return {}
        b = _bundle()
        t = b["episodes"][0]["inference_traces"][0]
        t["actions"].append({"type": "set_row_pan", "data": {"row": 0, "mode": "set", "value": 0.7}})
        runner = Runner()
        resolver = MixResolveService(runner=runner)
        resolver.resolve(project=t["project_state"], goal=t["goal"], actions=t["actions"], strict=t["strict"])
        rows = convert_bundle(b, resolver=resolver)
        self.assertEqual([r["feature_vector"] for r in rows[:2]], runner.features)

    def test_same_song_across_sessions_stays_in_one_split(self):
        first = _bundle(); second = copy.deepcopy(first); second["session_id"] = "different-session"
        a, b = convert_bundle(first)[0], convert_bundle(second)[0]
        self.assertEqual(a["group_id"], b["group_id"])
        self.assertEqual(a["split"], b["split"])
        self.assertNotEqual(a["example_id"], b["example_id"])

    def test_legacy_context_is_archived_but_excluded(self):
        b = _bundle(); b["episodes"][0].pop("inference_traces"); b.pop("segmentation_version")
        row = convert_bundle(b)[0]
        self.assertIsNone(row["feature_vector"])
        self.assertFalse(row["eligibility"]["mix_apply"])
        self.assertIn("missing_stable_source_group", row["exclusion_reasons"]["mix_apply"])

    def test_final_state_not_first_correction_sets_magnitude(self):
        b = _bundle()
        b["episodes"][0]["actions_raw"].append({"kind": "row_gain", "payload": {"row": 0, "new_gain": 1.8}})
        b["episodes"][0]["state_after"]["project_state"]["rows"][0]["mix"]["gain_0to3"] = 1.8
        self.assertAlmostEqual(convert_bundle(b)[0]["labels"]["magnitude_scale"], 0.8)

    def test_zero_master_value_is_not_replaced_by_default(self):
        from producer_capture_converter import _action_delta
        self.assertEqual(_action_delta({"master_gain_0to3": 0}, {"type": "set_master_gain", "data": {"mode": "set", "value": 0.3}}), 0.3)

    def test_validation_rejects_modified_shard(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / "bundle.json"; output = root / "output"
            source.write_text(json.dumps(_bundle()))
            manifest = run([str(source)], str(output))
            shard = output / manifest["shards"][0]["name"]
            shard.write_text(shard.read_text() + "\n")
            with self.assertRaisesRegex(ValueError, "checksum"):
                load_objective(output, "mix_apply")

    def test_readiness_requires_classes_in_training_and_holdouts(self):
        apply = ObjectiveRows([[0.] * 77] * 3, [1., 0., 1.], [1.] * 3, ["train", "validation", "test"])
        magnitude = ObjectiveRows([[0.] * 77] * 3, [1.] * 3, [1.] * 3, ["train", "validation", "test"])
        with self.assertRaisesRegex(ValueError, "Apply train"):
            validate_readiness(apply, magnitude, minimum_apply=1, minimum_magnitude=1)

    def test_removed_replaced_or_unidentified_track_cannot_train(self):
        for mutation, reason in (("removed", "target_track_removed"), ("replaced", "target_track_changed"), ("unknown", "missing_track_identity")):
            with self.subTest(mutation=mutation):
                b = _bundle()
                rows = b["episodes"][0]["state_after"]["project_state"]["rows"]
                if mutation == "removed":
                    rows.clear()
                elif mutation == "replaced":
                    rows[0]["row_id"] = "different-track-in-same-slot"
                else:
                    rows[0].pop("row_id")
                example = convert_bundle(b)[0]
                self.assertFalse(example["eligibility"]["mix_apply"])
                self.assertFalse(example["eligibility"]["mix_magnitude"])
                self.assertIn(reason, example["exclusion_reasons"]["mix_apply"])

    def test_inference_identity_takes_precedence_over_earlier_snapshot(self):
        b = _bundle()
        episode = b["episodes"][0]
        episode["inference_traces"][0]["row_identities"] = {"0": "new-vocal"}
        example = convert_bundle(b)[0]
        self.assertIn("target_track_changed", example["exclusion_reasons"]["mix_apply"])
        episode["state_after"]["project_state"]["rows"][0]["row_id"] = "new-vocal"
        self.assertTrue(convert_bundle(b)[0]["eligibility"]["mix_apply"])

    def test_partial_application_and_unfinished_episodes_are_excluded(self):
        for field, value, reason in (("capture_warning", "partial_ai_application", "capture_warning"), ("status", "active", "episode_not_complete")):
            b = _bundle()
            b["episodes"][0][field] = value
            example = convert_bundle(b)[0]
            self.assertFalse(example["eligibility"]["mix_apply"])
            self.assertFalse(example["eligibility"]["mix_magnitude"])
            self.assertIn(reason, example["exclusion_reasons"]["mix_apply"])


if __name__ == "__main__":
    unittest.main()
