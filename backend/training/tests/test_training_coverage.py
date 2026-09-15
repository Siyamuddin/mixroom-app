import copy
import ast
import csv
import json
import tempfile
import unittest
from pathlib import Path

from test_producer_capture_converter import _bundle
from test_plugin_training import plugin_bundle
from producer_capture_converter import convert_bundle, run, _sha256, _split
from common.mix_plugin_contract import proposed_value
from common.mix_resolve import _scale_action
from import_legacy_training import feature_columns, run as import_legacy
from train_mix_refine_models import load_objective


def inserted_bundle(master=False):
    b = plugin_bundle(master=master)
    e = b['episodes'][0]
    trace = e['inference_traces'][0]
    initial = trace['project_state']
    effects = initial['master_effects'] if master else initial['rows'][0]['effects']
    effect = effects.pop()
    action = trace['actions'][0]
    ensure = {'type': 'ensure_master_effect' if master else 'ensure_effect',
              'data': {'effect_name_contains': 'Compressor', **({} if master else {'row': 0})}}
    trace['actions'] = trace['resolved_actions'] = [ensure, action]
    e['parameter_executions'] = [{'action': copy.deepcopy(action), 'effect': effect}]
    return b


class TrainingCoverageTests(unittest.TestCase):
    def test_same_observed_plugin_correction_matches_historical_label_extractor(self):
        # Run the actual old extractor on its original snapshot shape.
        path = Path(__file__).resolve().parents[3] / 'tools/ai_mixing/prepare_dataset.py'
        tree = ast.parse(path.read_text())
        namespace = {}
        exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef)], type_ignores=[]), str(path), 'exec'), namespace)
        for master in (False, True):
            for final in (-18, -12, -6):
                b = plugin_bundle(master=master, final=final); e = b['episodes'][0]
                before = e['inference_traces'][0]['project_state']
                ai = copy.deepcopy(before)
                effects = ai['master_effects'] if master else ai['rows'][0]['effects']
                effects[0]['parameters'][0]['value'] = -24
                def historical(project):
                    return {'project_state': project, 'master': {'effects': project.get('master_effects', [])}}
                old_label, old_scale = namespace['_infer_scale_from_final_snapshot'](
                    e['inference_traces'][0]['actions'][0],
                    *[historical(p) for p in (before, ai, e['state_after']['project_state'])])
                row = convert_bundle(b)[0]
                self.assertTrue(row['eligibility']['mix_apply'], row['exclusion_reasons'])
                self.assertEqual(row['labels']['apply'], old_label)
                if old_label:
                    self.assertAlmostEqual(row['labels']['magnitude_scale'], old_scale)

    def test_all_historical_mixing_action_categories_still_produce_supervision(self):
        from producer_capture_converter import SUPPORTED_MODEL_ACTIONS
        covered = set()
        for master in (False, True):
            for suffix in ('gain', 'pan'):
                b = _bundle(); e = b['episodes'][0]; trace = e['inference_traces'][0]
                kind = f'set_{"master" if master else "row"}_{suffix}'
                action = {'type': kind, 'data': {'mode': 'set', 'value': 0.8, **({} if master else {'row': 0})}}
                trace['actions'] = trace['resolved_actions'] = [action]
                final = e['state_after']['project_state']
                if master: final['master_gain_0to3' if suffix == 'gain' else 'master_pan_0to1'] = 0.7
                else: final['rows'][0]['mix']['gain_0to3' if suffix == 'gain' else 'pan_0to1'] = 0.7
                row = convert_bundle(b)[0]
                self.assertTrue(row['eligibility']['mix_magnitude'], row['exclusion_reasons'])
                covered.add(kind)
            b = plugin_bundle(master=master)
            self.assertTrue(convert_bundle(b)[0]['eligibility']['mix_magnitude'])
            covered.add(b['episodes'][0]['inference_traces'][0]['actions'][0]['type'])
            for operation in ('ensure', 'delete', 'hard_reset'):
                b = plugin_bundle(master=master); e = b['episodes'][0]; trace = e['inference_traces'][0]
                kind = (f'hard_reset_{"master" if master else "row"}_fx' if operation == 'hard_reset'
                        else f'{operation}_{"master_" if master else ""}effect')
                action = {'type': kind, 'data': {'effect_name_contains': 'Compressor', **({} if master else {'row': 0})}}
                trace['actions'] = trace['resolved_actions'] = [action]
                target = trace['project_state'] if operation == 'ensure' else e['state_after']['project_state']
                if master: target['master_effects'] = []
                else: target['rows'][0]['effects'] = []
                row = convert_bundle(b)[0]
                self.assertTrue(row['eligibility']['mix_apply'], row['exclusion_reasons'])
                self.assertEqual(row['labels']['apply'], 1)
                self.assertFalse(row['eligibility']['mix_magnitude'])
                covered.add(kind)
        self.assertEqual(covered, SUPPORTED_MODEL_ACTIONS)

    def test_partial_batches_preserve_positive_and_negative_scalar_examples(self):
        for outcome in ('accepted', 'partial'):
            b = _bundle(); e = b['episodes'][0]; e['producer_outcome'] = outcome
            trace = e['inference_traces'][0]
            pan = {'type': 'set_row_pan', 'data': {'row': 0, 'mode': 'set', 'value': 0.8}}
            trace['actions'].append(pan); trace['resolved_actions'].append(pan)
            rows = convert_bundle(b)[:2]
            self.assertEqual([r['labels']['apply'] for r in rows], [1, 0])
            self.assertEqual([r['eligibility']['mix_apply'] for r in rows], [True, True])
            self.assertEqual([r['labels']['magnitude_scale'] for r in rows], [0.5, None])

    def test_continuous_plugin_direction_and_scalar_range_are_separate(self):
        for final, label, magnitude in ((-18, 1, 0.5), (-12, 0, None), (-6, 0, None), (-60, 1, None)):
            b = plugin_bundle(final=final); b['episodes'][0]['producer_outcome'] = 'partial'
            row = convert_bundle(b)[0]
            self.assertTrue(row['eligibility']['mix_apply'], row['exclusion_reasons'])
            self.assertEqual(row['labels']['apply'], label)
            self.assertEqual(row['labels']['magnitude_scale'], magnitude)

    def test_ensure_then_adjust_uses_actual_initial_value_without_feature_leakage(self):
        for master in (False, True):
            b = inserted_bundle(master); e = b['episodes'][0]; trace = e['inference_traces'][0]
            rows = convert_bundle(b)
            adjustment = rows[1]
            self.assertTrue(adjustment['eligibility']['mix_magnitude'], adjustment['exclusion_reasons'])
            self.assertEqual(adjustment['labels']['magnitude_scale'], 0.5)
            self.assertEqual(adjustment['final_plugin_target']['initial_value_source'], 'verified_parameter_execution')
            parameter = e['parameter_executions'][0]['effect']['parameters'][0]
            emitted = _scale_action(trace['project_state'], trace['actions'][1], 0.5, plugin_contract=True)
            self.assertEqual(emitted['data']['refinement_scale'], 0.5)
            self.assertEqual(proposed_value(parameter, emitted['data']), -18)
            # Changing execution/final values must never change model inputs.
            parameter['value'] = -10
            changed = convert_bundle(b)[1]
            self.assertEqual(adjustment['feature_vector'], changed['feature_vector'])
            self.assertEqual(adjustment['plugin_feature_vector'], changed['plugin_feature_vector'])
            e.pop('parameter_executions')
            self.assertFalse(convert_bundle(b)[1]['eligibility']['mix_magnitude'])

    def test_insert_execution_cannot_be_attached_to_replaced_instance(self):
        b = inserted_bundle()
        b['episodes'][0]['state_after']['project_state']['rows'][0]['effects'][0]['instanceId'] = 'replacement'
        self.assertIn('plugin_instance_removed_or_replaced', convert_bundle(b)[1]['exclusion_reasons']['mix_apply'])

    def test_reset_then_rebuild_chain_uses_new_instance_for_parameter_refinement(self):
        from common.mix_resolve import MixResolveService
        for master in (False, True):
            b = inserted_bundle(master); e = b['episodes'][0]; trace = e['inference_traces'][0]
            old = copy.deepcopy(e['parameter_executions'][0]['effect'])
            old['instanceId'] = 'old-instance'; old['parameters'][0]['value'] = -40
            if master: trace['project_state']['master_effects'] = [old]
            else: trace['project_state']['rows'][0]['effects'] = [old]
            reset = {'type': 'hard_reset_master_fx' if master else 'hard_reset_row_fx',
                     'data': {} if master else {'row': 0}}
            trace['actions'].insert(0, reset)
            rows = convert_bundle(b)[:3]
            self.assertEqual([r['labels']['apply'] for r in rows], [1, 1, 1])
            self.assertTrue(rows[2]['eligibility']['mix_magnitude'], rows[2]['exclusion_reasons'])
            self.assertEqual(rows[2]['labels']['magnitude_scale'], 0.5)
            class Runner:
                def feature_contract(self): return 'mix_refine_plugins_v2'
                def predict_apply_score(self, vector): return 0.9
                def predict_scalar(self, vector): return 0.5
                def observability_context(self): return {}
            response = MixResolveService(runner=Runner()).resolve(project=trace['project_state'],
                goal=trace['goal'], actions=trace['actions'], strict=True)
            self.assertFalse(response['fallback_used'])
            entry = response['debug_entries'][2]
            self.assertEqual(entry['after']['data']['refinement_scale'], entry['final_scale'])

    def test_deleted_plugin_restored_as_a_new_instance_is_a_negative(self):
        b = plugin_bundle(); e = b['episodes'][0]; trace = e['inference_traces'][0]
        action = {'type': 'delete_effect', 'data': {'row': 0, 'effect_name_contains': 'Compressor'}}
        trace['actions'] = trace['resolved_actions'] = [action]
        e['state_after']['project_state']['rows'][0]['effects'][0]['instanceId'] = 'restored-instance'
        row = convert_bundle(b)[0]
        self.assertTrue(row['eligibility']['mix_apply'])
        self.assertEqual(row['labels']['apply'], 0)

    def test_removed_insert_is_a_negative_example(self):
        b = inserted_bundle(); e = b['episodes'][0]
        e['producer_outcome'] = 'partial'
        e['state_after']['project_state']['rows'][0]['effects'] = []
        row = convert_bundle(b)[0]
        self.assertTrue(row['eligibility']['mix_apply'])
        self.assertEqual(row['labels']['apply'], 0)

    def test_independent_traces_train_but_repeated_targets_do_not(self):
        b = _bundle(); traces = b['episodes'][0]['inference_traces']
        second = copy.deepcopy(traces[0])
        second['actions'] = second['resolved_actions'] = [{'type': 'set_master_gain', 'data': {'mode': 'set', 'value': 1.5}}]
        traces.append(second)
        rows = convert_bundle(b)[:2]
        self.assertTrue(all(r['eligibility']['mix_apply'] for r in rows))
        self.assertEqual([r['source']['inference_trace_index'] for r in rows], [0, 1])
        traces.append(copy.deepcopy(traces[0]))
        self.assertIn('ambiguous_proposal_target', convert_bundle(b)[0]['exclusion_reasons']['mix_apply'])

    def test_unreviewed_sessions_still_do_not_invent_acceptance(self):
        for outcome in ('not_evaluated', 'experimenting', None):
            b = plugin_bundle(); b['episodes'][0]['producer_outcome'] = outcome
            self.assertFalse(convert_bundle(b)[0]['eligibility']['mix_apply'])

    def test_historical_rows_can_train_alongside_v4_with_shared_song_groups(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root / 'capture.json'; source.write_text(json.dumps(_bundle()))
            run([str(source)], str(root / 'v4'))
            path = root / 'legacy.csv'; columns = feature_columns()
            raw = {**dict.fromkeys(columns, 0), 'project_id': 'old-song', 'session_id': 'old-session',
                   'action_type': 'adjust_effect_param_by_name', 'label_apply': 1, 'label_magnitude_scale': 0.75}
            with path.open('w') as handle:
                writer = csv.DictWriter(handle, fieldnames=list(raw)); writer.writeheader(); writer.writerow(raw)
            with self.assertRaisesRegex(ValueError, 'group-map'):
                import_legacy(path, root / 'unsafe', dataset=root / 'v4')
            manifest = import_legacy(path, root / 'combined', dataset=root / 'v4', groups={'old-song': 'same-song'})
            self.assertEqual(manifest['historical_examples'], 1)
            apply = load_objective(root / 'combined', 'mix_apply')
            self.assertEqual(len(apply.labels), 2)
            self.assertEqual(set(apply.splits), {_split(_sha256('same-song'))})
            magnitude = load_objective(root / 'combined', 'mix_magnitude')
            self.assertEqual(magnitude.labels, [0.5, 0.75])
            with self.assertRaisesRegex(ValueError, 'plugin feature contract'):
                load_objective(root / 'combined', 'mix_apply', plugins=True)
