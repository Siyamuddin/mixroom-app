import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from test_plugin_training import plugin_bundle
from human_magnitude_data import extract
from human_selection_data import extract_selection
from train_human_refinement import train
from evaluate_producer_models import CandidateRunner
from common.mix_resolve import MixResolveService
from common.mix_magnitude_contract import fingerprint, features as magnitude_features
from common.mix_selection_contract import CONTRACT, features, structural_descriptor, runtime_target, choice_coordinate
from common.plugin_identity import canonical_plugin_id

ROOT=Path(__file__).resolve().parents[3]
CLASSIFIER=ROOT/'backend/llm_proxy/src/models/mix_apply_classifier_official_sessions_20260330_seed1.onnx'

class HumanSelectionTests(unittest.TestCase):
    def bundle(self, **kwargs):
        b=plugin_bundle(**kwargs);b['ended_at']='now';return b

    def test_shared_plugin_identity_fixtures(self):
        rows=json.loads((ROOT/'test/fixtures/producer_plugin_identity.json').read_text())
        for r in rows:
            self.assertEqual(canonical_plugin_id(r['raw']),r['canonical'])
            self.assertEqual(canonical_plugin_id(r['canonical']),r['canonical'])

    def test_raw_and_captured_plugin_ids_have_identical_training_features(self):
        raw=self.bundle();raw['episodes'][0]['inference_traces']=[]
        for key in ('state_before','state_after'):
            raw['episodes'][0][key]['project_state']['rows'][0]['effects'][0]['effectId']='/Library/Audio/Plug-Ins/VST3/Example.vst3'
        captured=copy.deepcopy(raw)
        for key in ('state_before','state_after'):
            e=captured['episodes'][0][key]['project_state']['rows'][0]['effects'][0];e['effectId']=canonical_plugin_id(e['effectId'])
        a=extract(raw)[0][0];b=extract(captured)[0][0]
        self.assertEqual(a['descriptor'],b['descriptor']);self.assertEqual(a['features'],b['features'])
        self.assertEqual(extract_selection(raw)[0][0]['features'],extract_selection(captured)[0][0]['features'])

    def test_untouched_controls_do_not_become_negatives(self):
        b=self.bundle();b['episodes'][0]['inference_traces']=[];b['episodes'][0]['actions_raw']=[]
        rows,_=extract_selection(b)
        self.assertTrue(rows);self.assertEqual({r['label'] for r in rows},{1})

    def test_reverted_auditioned_proposal_is_negative(self):
        rows,_=extract_selection(self.bundle(final=-12))
        self.assertEqual({r['label'] for r in rows},{0})
        self.assertEqual(rows[0]['label_provenance'],'auditioned_ai_proposal')

    def test_unexecuted_proposal_is_not_rejection_evidence(self):
        bundle = self.bundle(final=-12)
        bundle['episodes'][0]['inference_traces'][0]['resolved_actions'] = []
        self.assertEqual(extract_selection(bundle)[0], [])

    def test_repeated_trace_target_is_ambiguous(self):
        bundle = self.bundle(final=-12)
        traces = bundle['episodes'][0]['inference_traces']
        traces.append(copy.deepcopy(traces[0]))
        rows, exclusions = extract_selection(bundle)
        self.assertEqual(rows, [])
        self.assertEqual(exclusions['repeated_observed_choice_target'], 2)

    def test_rejected_reset_blocks_effect_changes_but_preserves_gain(self):
        descriptor = structural_descriptor('reset')
        class Runner:
            selection_controls = {fingerprint(descriptor): descriptor}
            magnitude_controls = {}
            def feature_contract(self): return CONTRACT
            def magnitude_contract(self): return 'mix_magnitude_human_v3'
            def predict_apply_score(self, x): return .1
            def observability_context(self): return {}
        before = self.bundle()['episodes'][0]['state_before']['project_state']
        actions = [
            {'type': 'hard_reset_row_fx', 'data': {'row': 0}},
            {'type': 'ensure_effect', 'data': {'row': 0, 'effect_name_contains': 'Reverb'}},
            {'type': 'set_row_gain', 'data': {'row': 0, 'mode': 'set', 'value': .8}},
        ]
        result = MixResolveService(Runner()).resolve(project=before, goal={}, actions=actions, strict=True)
        self.assertFalse(result['fallback_used'])
        self.assertEqual([a['type'] for a in result['actions']], ['set_row_gain'])
        self.assertEqual(result['debug_entries'][1]['decision'], 'dependent_action_drop')

    def test_rejected_partial_and_unknown_do_not_get_wholesale_positive_labels(self):
        for outcome,expected in [('rejected',{0}),('partial',{1}),('not_evaluated',set())]:
            b=self.bundle();b['episodes'][0]['producer_outcome']=outcome
            rows,_=extract_selection(b);self.assertEqual({r['label'] for r in rows},expected)

    def test_context_and_goal_are_inputs_but_annotations_are_not_inferred(self):
        b=self.bundle();b['episodes'][0]['inference_traces']=[];b['episodes'][0]['actions_raw']=[]
        b['episodes'][0]['diagnoses']=['dynamics'];b['episodes'][0]['strategies']=['control_dynamics']
        row=extract_selection(b)[0][0]
        self.assertEqual(row['goal'],{'intents':[{'kind':'compressor'}]})
        project=copy.deepcopy(row['state_before']);project['rows'][0]['role_probs']={'drums':1.0}
        self.assertNotEqual(row['features'],features(project,row['descriptor'],row['scope'],row['direction'],row['choice'],row['goal']))
        self.assertNotEqual(row['features'],features(row['state_before'],row['descriptor'],row['scope'],row['direction'],row['choice'],{'intents':[{'kind':'reverb'}]}))

    def test_missing_negative_data_fails_instead_of_fabricating_labels(self):
        b=self.bundle();b['episodes'][0]['inference_traces']=[];b['episodes'][0]['actions_raw']=[]
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,'observed rejected'):
                train(extract(b)[0],Path(tmp)/'models',classifier=CLASSIFIER,development=True,selection_rows=extract_selection(b)[0])

    def test_classifier_rejects_insertion_and_dependent_parameter_even_when_strict(self):
        descriptor=structural_descriptor('insert',{'name':'Reverb','effectId':'Reverb'})
        class Runner:
            selection_controls={fingerprint(descriptor):descriptor};magnitude_controls={}
            def feature_contract(self):return CONTRACT
            def magnitude_contract(self):return 'mix_magnitude_human_v3'
            def predict_apply_score(self,x):return .1
            def observability_context(self):return {}
        before=self.bundle()['episodes'][0]['state_before']['project_state']
        actions=[{'type':'ensure_effect','data':{'row':0,'effect_name_contains':'Reverb'}},
                 {'type':'adjust_effect_param_by_name','data':{'row':0,'effect_name_contains':'Reverb','param_name':'Mix','mode':'set','value':20}}]
        result=MixResolveService(Runner()).resolve(project=before,goal={},actions=actions,strict=True)
        self.assertFalse(result['fallback_used']);self.assertEqual(result['actions'],[])
        self.assertEqual([r['decision'] for r in result['debug_entries']],['human_selection_drop','dependent_action_drop'])

    def test_choice_value_is_part_of_classifier_input(self):
        b=self.bundle();before=b['episodes'][0]['state_before']['project_state']
        p=before['rows'][0]['effects'][0]['parameters'][0];p.update(type='choice',value='Soft',choices=['Soft','Hard'])
        from common.mix_magnitude_contract import parameter_descriptor
        d=parameter_descriptor(before['rows'][0]['effects'][0],p)
        actions=[{'type':'adjust_effect_param_by_name','data':{'row':0,'effect_name_contains':'Compressor','param_name':'Threshold','mode':'set','value_norm':1}}]
        target=runtime_target(before,actions[0],actions,0,{fingerprint(d):d})
        self.assertIsNotNone(target);self.assertEqual(target[-1],1)

    def test_captured_third_party_plugin_model_runs_on_raw_runtime_id(self):
        positive=self.bundle();positive['episodes'][0]['inference_traces']=[];positive['episodes'][0]['actions_raw']=[]
        negative=self.bundle(proposal=-6,final=-12);negative['session_id']='negative';negative['episodes'][0]['producer_outcome']='rejected'
        raw_id='/Library/Audio/Plug-Ins/VST3/Example.vst3'
        for b in (positive,negative):
            for key in ('state_before','state_after'):
                b['episodes'][0][key]['project_state']['rows'][0]['effects'][0]['effectId']=canonical_plugin_id(raw_id)
            for trace in b['episodes'][0].get('inference_traces',[]):
                trace['project_state']['rows'][0]['effects'][0]['effectId']=canonical_plugin_id(raw_id)
        choices=extract_selection(positive)[0]+extract_selection(negative)[0]
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ,{'MIX_ALLOW_DEVELOPMENT_MODELS':'true'}):
            output=Path(tmp)/'models';train(extract(positive)[0],output,classifier=CLASSIFIER,development=True,selection_rows=choices)
            runner=CandidateRunner(output)
            project=copy.deepcopy(positive['episodes'][0]['state_before']['project_state'])
            project['rows'][0]['effects'][0]['effectId']=raw_id
            action={'type':'adjust_effect_param_by_name','data':{'row':0,'effect_name_contains':'Compressor','param_name':'Threshold','mode':'set','value':-18}}
            response=MixResolveService(runner).resolve(project=project,goal={},actions=[action],strict=True)
            self.assertFalse(response['fallback_used'])
            self.assertTrue(response['debug_entries'][0]['selection_supported'])
            self.assertEqual(response['debug_entries'][0]['decision'],'human_magnitude')
            self.assertNotIn(raw_id,json.dumps(runner.selection_controls))
            self.assertNotIn(raw_id,json.dumps(runner.magnitude_controls))

    def test_selection_evaluation_refuses_candidate_training_song_reuse(self):
        from evaluate_human_selection import evaluate
        row=extract_selection(self.bundle())[0][0]
        class Runner:
            training_groups={row['group']}
            def feature_contract(self):return CONTRACT
        with self.assertRaisesRegex(ValueError,'used to train'):
            evaluate([row],Runner(),Runner(),split='external')
