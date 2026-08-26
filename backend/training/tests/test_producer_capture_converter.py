from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

TRAINING_ROOT = Path(__file__).resolve().parents[1]
if str(TRAINING_ROOT) not in sys.path:
    sys.path.insert(0, str(TRAINING_ROOT))

from producer_capture_converter import convert_bundle, run  # noqa: E402
from train_mix_refine_models import load_objective  # noqa: E402


def _project() -> dict:
    return {
        "bpm": 120.0,
        "max_rows": 1,
        "master_gain_0to3": 1.0,
        "master_pan_0to1": 0.5,
        "rows": [
            {
                "row": 0,
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
        "episodes": [
            {
                "state_before": {"project_state": _project()},
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
        episode["status"] = "rejected"
        episode["outcome_signals"] = {"rejected_by_undo": True}
        examples = convert_bundle(bundle)
        self.assertEqual(examples[0]["labels"]["apply"], 0)
        self.assertEqual(examples[0]["labels"]["magnitude_scale"], 0.0)
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
            self.assertEqual(len(apply.features), 2)
            self.assertEqual(len(magnitude.features), 1)
            self.assertAlmostEqual(magnitude.labels[0], 0.5)


if __name__ == "__main__":
    unittest.main()
