from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
import os
import subprocess
import sys
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
    @unittest.skipUnless(importlib.util.find_spec("pandas"), "Install training requirements for historical preprocessing")
    def test_original_v3_capture_to_csv_to_new_trainer_to_existing_runtime(self):
        from import_legacy_training import run as import_legacy
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); captures = root / 'old'; captures.mkdir()
            counts = {"train": 0, "validation": 0, "test": 0}
            index = 0
            while min(counts.values()) < 3:
                group = f'old-reviewed-song-{index}'; index += 1
                split = _split(_sha256(group))
                if counts[split] >= 3:
                    continue
                counts[split] += 1
                cycles = []
                for accepted in (True, False):
                    e = _bundle()['episodes'][0]
                    before = copy.deepcopy(e['state_before'])
                    ai = copy.deepcopy(before); ai['project_state']['rows'][0]['mix']['gain_0to3'] = 2
                    final = copy.deepcopy(before); final['project_state']['rows'][0]['mix']['gain_0to3'] = 1.5 if accepted else 1
                    cycles.append({'cycle_id': str(accepted), 'status': 'complete',
                        'before_prompt_snapshot': before, 'ai_after_snapshot': ai,
                        'producer_final_snapshot': final, 'resolved_ai_actions': e['inference_traces'][0]['actions']})
                (captures / f'{index}.json').write_text(json.dumps({
                    'schema_version': 3, 'project_id': group, 'session_id': f'old-{index}', 'prompt_cycles': cycles}))
            script = Path(__file__).resolve().parents[3] / 'tools/ai_mixing/prepare_dataset.py'
            prepared = subprocess.run([sys.executable, str(script), '--sessions-dir', str(captures),
                                       '--out-csv', str(root / 'old.csv')], capture_output=True, text=True)
            self.assertEqual(prepared.returncode, 0, prepared.stdout + prepared.stderr)
            imported = import_legacy(root / 'old.csv', root / 'dataset')
            self.assertEqual(imported['historical_examples'], 18)
            report = train(root / 'dataset', root / 'models', feature_contract='mix_refine_v1',
                           minimum_apply=2, minimum_magnitude=2)
            self.assertEqual(report['onnx_runtime_parity'], 'passed')
            runner = CandidateRunner(root / 'models')
            trace = _bundle()['episodes'][0]['inference_traces'][0]
            response = MixResolveService(runner=runner).resolve(project=trace['project_state'],
                goal=trace['goal'], actions=trace['actions'], strict=True)
            self.assertFalse(response['fallback_used'], response)
            self.assertEqual(runner.feature_contract(), 'mix_refine_v1')

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
            self.assertEqual(report["magnitude_estimator"], "gradient_boosting")
            compatible = train(root / "dataset", root / "models77", minimum_apply=3, minimum_magnitude=3,
                               feature_contract="mix_refine_v1")
            self.assertEqual(compatible["feature_count"], 77)
            self.assertEqual(compatible["runtime_targets"], ["remote", "local_dart"])
            self.assertEqual(compatible["onnx_runtime_parity"], "passed")
            compatible_runner = CandidateRunner(root / "models77")
            self.assertEqual(compatible_runner.feature_contract(), "mix_refine_v1")
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
