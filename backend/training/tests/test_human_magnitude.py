import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from test_plugin_training import plugin_bundle
from test_producer_capture_converter import _bundle
from human_magnitude_data import extract, extract_historical
from human_selection_data import extract_selection
from train_human_refinement import train, review, paths
from common.mix_magnitude_contract import features, fingerprint, control_action, runtime_target, refine_amount, FEATURE_COUNT
from common.mix_resolve import MixResolveService, OnnxMixModelRunner
from evaluate_producer_models import CandidateRunner
from evaluate_human_magnitude import evaluate, probe

CLASSIFIER=Path(__file__).resolve().parents[2]/'llm_proxy/src/models/mix_apply_classifier_official_sessions_20260330_seed1.onnx'

class HumanMagnitudeTests(unittest.TestCase):
    def bundle(self, plugin=True):
        b=plugin_bundle() if plugin else _bundle()
        b['ended_at']='2026-09-14T00:00:00Z';b['episodes'][0]['inference_traces']=[]
        b['episodes'][0]['diagnoses']=[]
        return b

    def test_manual_amount_uses_actual_range_without_proposal(self):
        rows, reasons=extract(self.bundle())
        self.assertEqual(len(rows),1,reasons)
        self.assertAlmostEqual(rows[0]['target'],6/60)
        self.assertEqual(len(rows[0]['features']),FEATURE_COUNT)

    def test_final_magnitude_does_not_leak_into_features(self):
        b=self.bundle();a=extract(b)[0][0]
        b['episodes'][0]['state_after']['project_state']['rows'][0]['effects'][0]['parameters'][0]['value']=-30
        other=extract(b)[0][0]
        self.assertEqual(a['features'],other['features']);self.assertNotEqual(a['target'],other['target'])

    def test_inserted_preset_uses_final_coordinate_without_fake_start(self):
        b=self.bundle();b['episodes'][0]['state_before']['project_state']['rows'][0]['effects']=[]
        rows,reasons=extract(b)
        self.assertEqual(len(rows),1)
        self.assertIsNone(rows[0]['initial_value']);self.assertTrue(rows[0]['descriptor']['inserted'])
        self.assertAlmostEqual(rows[0]['target'],.7)
        self.assertIn('discrete_action_archived_not_magnitude',reasons)

    def test_new_hosted_plugin_needs_loaded_identity_before_refinement(self):
        from common.mix_selection_contract import runtime_target as selection_target, structural_descriptor
        b = self.bundle()
        episode = b['episodes'][0]
        episode['state_before']['project_state']['rows'][0]['effects'] = []
        for identity, can_refine in [('plugin_uid_v1_' + 'a' * 64, False), ('Compressor', True)]:
            effect = episode['state_after']['project_state']['rows'][0]['effects'][0]
            effect['effectId'] = identity
            rows, _ = extract(b)
            row = rows[0]
            actions = probe(row)
            descriptor = row['descriptor']
            controls = {fingerprint(descriptor): descriptor}
            args = (row['state_before'], actions[-1], actions, len(actions) - 1, controls)
            self.assertEqual(runtime_target(*args) is not None, can_refine)
            self.assertEqual(selection_target(*args) is not None, can_refine)
            insertion = structural_descriptor('insert', effect)
            target = selection_target(row['state_before'], actions[0], actions, 0,
                                      {fingerprint(insertion): insertion})
            self.assertEqual(target is not None, can_refine)

    def test_unknown_partial_and_undo_are_not_good_labels(self):
        for outcome in ('partial','rejected','not_evaluated','experimenting'):
            b=self.bundle();b['episodes'][0]['producer_outcome']=outcome
            self.assertEqual(extract(b)[0],[])
        b=self.bundle();b['episodes'][0]['outcome_signals']={'undo_redo_observed':True}
        self.assertEqual(extract(b)[0],[])

    def test_direction_and_bounds_survive_extreme_prediction(self):
        row=extract(self.bundle())[0][0];actions=probe(row)
        t=runtime_target(row['state_before'],actions[-1],actions,len(actions)-1,{fingerprint(row['descriptor']):row['descriptor']})
        result=refine_amount(actions[-1],t,100,1)
        value=result['data']['value']
        self.assertLess(value,row['initial_value']);self.assertGreaterEqual(value,-60)
        self.assertLessEqual(abs(value-row['initial_value']),15)

    def test_classifier_confidence_still_attenuates(self):
        row=extract(self.bundle())[0][0];actions=probe(row)
        t=runtime_target(row['state_before'],actions[-1],actions,0,{fingerprint(row['descriptor']):row['descriptor']})
        strong=refine_amount(actions[-1],t,.1,1)['data']['value']
        weak=refine_amount(actions[-1],t,.1,.2)['data']['value']
        self.assertLess(abs(weak-row['initial_value']),abs(strong-row['initial_value']))

    def test_reset_before_parameter_keeps_proposal(self):
        row=extract(self.bundle())[0][0];action=control_action(row['descriptor'],row['scope'])
        reset={'type':'hard_reset_row_fx','data':{'row':0,'force_individual_row':True}}
        self.assertIsNone(runtime_target(row['state_before'],action,[reset,action],1,{fingerprint(row['descriptor']):row['descriptor']}))

    def test_normal_export_requires_independent_training_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,'10 training songs'):
                train(extract(self.bundle())[0],Path(tmp)/'models',classifier=CLASSIFIER)

    def test_both_real_onnx_models_train_and_decoder_matches(self):
        rows=extract(self.bundle())[0]
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'models'
            positive=self.bundle();negative=plugin_bundle(proposal=-6,final=-12)
            negative['session_id']='rejected-session';negative['ended_at']='now';negative['episodes'][0]['producer_outcome']='rejected'
            choices=extract_selection(positive)[0]+extract_selection(negative)[0]
            report=train(rows,output,classifier=CLASSIFIER,development=True,selection_rows=choices)
            self.assertTrue(report['classifier_retrained']);self.assertEqual(len(list(output.glob('*.onnx'))),2)
            with patch.dict(os.environ,{'MIX_ALLOW_DEVELOPMENT_MODELS':'false'}):
                with self.assertRaisesRegex(ValueError,'Development model'):CandidateRunner(output).feature_contract()
            with patch.dict(os.environ,{'MIX_ALLOW_DEVELOPMENT_MODELS':'true'}):
                runner=CandidateRunner(output);service=MixResolveService(runner)
                response=service.resolve(project=rows[0]['state_before'],goal={},actions=probe(rows[0]),strict=True)
                self.assertFalse(response['fallback_used'])
                self.assertEqual(response['debug_entries'][0]['decision'],'human_magnitude')
                self.assertAlmostEqual(response['actions'][0]['data']['value'],-18,places=4)
                self.assertEqual(runner.feature_contract(),'mix_selection_human_v1')
                self.assertEqual(runner.magnitude_contract(),'mix_magnitude_human_v3')
                with self.assertRaisesRegex(ValueError,'used to train'):
                    evaluate(rows,runner,OnnxMixModelRunner(),split='external')

    def test_legacy_final_snapshots_keep_weaker_provenance(self):
        b=self.bundle(False);e=b['episodes'][0]
        legacy={'schema_version':3,'session_id':'old','project_id':'song','prompt_cycles':[{'cycle_id':'one','status':'complete',
            'final_captured_at':'now','before_prompt_snapshot':e['state_before'],'producer_final_snapshot':e['state_after']}]}
        rows,_=extract_historical(legacy)
        self.assertEqual(len(rows),1);self.assertFalse(rows[0]['producer_confirmed_good'])
        self.assertEqual(rows[0]['source'],'historical_final_snapshot')
        legacy['prompt_cycles'][0]['producer_final_snapshot']={}
        self.assertEqual(extract_historical(legacy)[0],[])

    def test_unseen_controls_never_get_guessed_magnitude(self):
        row=extract(self.bundle())[0][0];actions=probe(row)
        self.assertIsNone(runtime_target(row['state_before'],actions[0],actions,0,{}))

    def test_track_audio_context_is_present(self):
        row=extract(self.bundle(False))[0][0];project=copy.deepcopy(row['state_before'])
        project['rows'][0]['role_probs']={'bass':1}
        self.assertNotEqual(row['features'],features(project,row['descriptor'],row['scope'],row['direction']))

    def test_discrete_parameters_do_not_train_regression(self):
        b=self.bundle()
        for name in ('state_before','state_after'):
            p=b['episodes'][0][name]['project_state']['rows'][0]['effects'][0]['parameters'][0]
            p.update(type='bool',value=name=='state_after')
        rows,reasons=extract(b)
        self.assertEqual(rows,[])
        self.assertIn('discrete_action_archived_not_magnitude',reasons)

    def test_duplicate_track_ids_are_rejected(self):
        b=self.bundle(False)
        for name in ('state_before','state_after'):
            rows=b['episodes'][0][name]['project_state']['rows']
            duplicate=copy.deepcopy(rows[0]);duplicate['row']=1;rows.append(duplicate)
        rows,reasons=extract(b)
        self.assertEqual(rows,[])
        self.assertIn('ambiguous_track_identity',reasons)

    def test_copied_capture_is_not_double_weighted(self):
        b=self.bundle()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);a=root/'a.json';other=root/'copy.json'
            a.write_text(json.dumps(b));other.write_text(json.dumps(b))
            report=review([a,other],root/'review',classifier=CLASSIFIER,train_requested=False)
            self.assertEqual(report['examples'],1)

    def test_discovers_downloaded_s3_bundles_and_local_sessions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);uploaded=root/'structured'/'session=one';uploaded.mkdir(parents=True)
            remote=uploaded/'bundle.json';remote.write_text('{}')
            local=root/'session-local.json';local.write_text('{}')
            (root/'report.json').write_text('{}')
            self.assertEqual(set(paths([tmp])),{remote,local})
