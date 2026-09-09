from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
import os
from unittest.mock import patch
from pathlib import Path

from test_producer_capture_converter import _bundle
from test_plugin_training import plugin_bundle
from common.mix_resolve import MixResolveService, OnnxMixModelRunner
from evaluate_producer_models import evaluate, CandidateRunner
from producer_capture_converter import _sha256, _split, run
from train_mix_refine_models import train


@unittest.skipUnless(all(importlib.util.find_spec(name) for name in ("sklearn", "skl2onnx", "onnxruntime")), "Install training requirements for ONNX integration test")
class ProducerModelExportTests(unittest.TestCase):
    def test_capture_to_training_to_production_onnx_decoder(self):
        # Synthetic fixtures prove format/runtime compatibility, not audio quality.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            captures = root / "captures"
            captures.mkdir()
            counts = {"train": 0, "validation": 0, "test": 0}
            index = 0
            while min(counts.values()) < 3:
                group = f"synthetic-song-{index}"
                index += 1
                split = _split(_sha256(group))
                if counts[split] >= 3:
                    continue
                counts[split] += 1
                for accepted in (True, False):
                    b = copy.deepcopy(plugin_bundle() if counts[split] % 2 else _bundle())
                    b["session_id"] = f"synthetic-{index}-{accepted}"
                    b["project_ref"] = group
                    e = b["episodes"][0]
                    e["producer_outcome"] = "accepted" if accepted else "rejected"
                    e["actions_raw"] = e["actions_raw"][:1]
                    e["inference_traces"][0]["goal"]["intensity"] = 0.4 if accepted else 0.9
                    e["state_after"]["project_state"]["rows"][0]["mix"]["gain_0to3"] = 1.4 if accepted else 1.0
                    (captures / f'{b["session_id"]}.json').write_text(json.dumps(b))
            dataset = root / "dataset"
            run([str(captures)], str(dataset))
            report = train(dataset, root / "models", minimum_apply=2, minimum_magnitude=2)
            self.assertEqual(report["onnx_runtime_parity"], "passed")
            self.assertFalse(report["publication_approved"])
            self.assertIn("apply_test_auc", report)
            self.assertIn("magnitude_test_unchanged_mae", report)
            self.assertEqual(report["feature_count"], 141)
            with patch.dict(os.environ, {
                "MIX_APPLY_MODEL_PATH": str(root / "models" / report["models"]["apply"]),
                "MIX_MAGNITUDE_MODEL_PATH": str(root / "models" / report["models"]["magnitude"]),
                "MIX_MODEL_BUNDLE_VERSION": "test-plugin-models",
            }):
                runner = OnnxMixModelRunner()
                trace = plugin_bundle()["episodes"][0]["inference_traces"][0]
                response = MixResolveService(runner=runner).resolve(
                    project=trace["project_state"], goal=trace["goal"], actions=trace["actions"], strict=True)
                self.assertFalse(response["fallback_used"], response)
                self.assertEqual(response["observability"]["mix_feature_contract_version"], "mix_refine_plugins_v2")
                self.assertEqual(response["observability"]["mix_magnitude_model_bundle_version"], "test-plugin-models")
                self.assertEqual(response["actions"][0]["data"]["param_name"], "Threshold")
                self.assertTrue(-60 <= response["actions"][0]["data"]["value"] <= 0)

                import onnx
                bad = root / "wrong-contract.onnx"
                model = onnx.load(str(root / "models" / report["models"]["magnitude"]))
                onnx.helper.set_model_props(model, {"mix_feature_contract_version": "mix_refine_v1"})
                onnx.save(model, str(bad))
                with patch.dict(os.environ, {"MIX_MAGNITUDE_MODEL_PATH": str(bad)}):
                    failed = MixResolveService(runner=OnnxMixModelRunner()).resolve(
                        project=trace["project_state"], goal=trace["goal"], actions=trace["actions"], strict=True)
                    self.assertTrue(failed["fallback_used"])
                    self.assertEqual(failed["actions"], trace["actions"])
            assets = Path(__file__).resolve().parents[3] / "assets" / "models"
            with patch.dict(os.environ, {
                "MIX_APPLY_MODEL_PATH": str(assets / "mix_apply_classifier_official_sessions_20260330_seed1.onnx"),
                "MIX_MAGNITUDE_MODEL_PATH": str(assets / "mix_magnitude_regressor_official_sessions_20260330_seed1.onnx"),
            }):
                legacy = OnnxMixModelRunner()
                self.assertEqual(legacy.feature_contract(), "mix_refine_v1")
                response = MixResolveService(runner=legacy).resolve(
                    project=trace["project_state"], goal=trace["goal"], actions=trace["actions"], strict=True)
                self.assertFalse(response["fallback_used"], response)

            replay = evaluate([json.loads(file.read_text()) for file in captures.glob("*.json")],
                              candidate=CandidateRunner(root / "models"), baseline=legacy)
            self.assertGreater(replay["examples"], 0)
            self.assertEqual(replay["models"]["candidate"]["mix_feature_contract_version"], "mix_refine_plugins_v2")
            self.assertEqual(replay["models"]["baseline"]["mix_feature_contract_version"], "mix_refine_v1")
