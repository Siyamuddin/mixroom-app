"""Retained synthetic failures, exact repair preservation, frozen comparison."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tool/ai_v3_eval'))
import evaluate_row_rebuild as original
import evaluate_row_rebuild_revision as evaluation
import row_rebuild_revision as revision
from row_rebuild_candidate import candidate as previous_candidate
from score_row_rebuild import scope
from common import v3_pitch_repair as repair
from common import v3_server_contract as contract
from common.llm_contract import build_openai_responses_request
import test_pitch_repair_integration as integration
from test_bounded_pitch_repair import mocked_patch

FIXTURE = Path(__file__).with_name('fixtures') / 'row_rebuild_observed_v2.json'


def cases():
    return json.loads(FIXTURE.read_text())['cases']


def request(case):
    body = case['request']
    return contract.validate_context_request(body, raw_body_bytes=len(original.canonical(body).encode()))


class RowRebuildRevisionTests(unittest.TestCase):
    def test_independent_substitutions_both_instruction_variants(self):
        for filename in ('v3_instructions.txt', 'v3_instructions_resource_refs.txt'):
            runtime = (ROOT / 'backend/llm_proxy/src/common/v3_contract_assets' / filename).read_text()
            previous = previous_candidate(revision.historical_instructions(runtime))
            changed = revision.candidate(previous)
            self.assertEqual(runtime, changed, 'Runtime must use the exact tested 16/20 wording')
            self.assertEqual(changed, revision.revise_capacity(revision.revise_pitch(previous)))
            self.assertEqual(changed.replace(revision.CAPACITY, revision.PREVIOUS_CAPACITY)
                             .replace(revision.PITCH, revision.ORIGINAL_PITCH), previous)
            self.assertEqual(runtime.splitlines()[-1], changed.splitlines()[-1])
            with self.assertRaises(ValueError):
                revision.candidate(changed)

    def test_frozen_requests_and_settings(self):
        self.assertEqual(evaluation.manifest(), evaluation.manifest())
        self.assertEqual(len(evaluation.manifest()['schedule']), 40)
        for index in range(5):
            body, valid, old, new = evaluation.prepare(index)
            self.assertEqual(body, original.prepare(index)[0])
            self.assertEqual(old, original.prepare(index)[3])
            a, b = [build_openai_responses_request(item) for item in (old, new)]
            self.assertEqual({k: v for k, v in a.items() if k != 'instructions'},
                             {k: v for k, v in b.items() if k != 'instructions'})
            self.assertEqual(new['max_output_tokens'], 16384)
            actual = contract.build_provider_request(valid, model=original.MODEL,
                reasoning_effort='low', max_output_tokens=16384)
            self.assertEqual(actual, new, 'Adopt only the exact evaluated request body')

    def test_removed_row_repair_opt_in_cannot_change_safe_rejection(self):
        context_class = integration._LambdaContext
        def context(*args, **kwargs):
            result = context_class(*args, **kwargs)
            result._local_v3_row_repair_enabled = True
            return result
        for case in cases():
            if case['expected_error'] not in ('v3_plan_row_capacity_exceeded', 'v3_plan_capability_invalid'):
                continue
            with self.subTest(case=case['name']), mock.patch.object(
                    integration, '_LambdaContext', side_effect=context):
                response, provider, usage, log, _ = integration.PitchRepairIntegrationTests().invoke(
                    body=case['request'], plan=case['plan'], second={}, times=(100.,))
                self.assertEqual(response['statusCode'], 502)
                self.assertEqual(len(provider.request_bodies), 1)
                self.assertEqual(len(usage.release_calls), 1)
                self.assertEqual(usage.finalize_calls, [])
                self.assertNotIn('plan', json.loads(response['body']))
                self.assertFalse(any(k.startswith('v3_row_repair') for k in log))

    def test_all_retained_failure_attributions(self):
        self.assertEqual(len(cases()), 7)
        for case in cases():
            with self.subTest(case=case['name']):
                valid = request(case)
                if not case['expected_error']:
                    contract.validate_plan_capabilities(case['plan'], valid['capability_surface'])
                    self.assertFalse(scope(dict(case='partial_rebuild', context=case['request']['core_context'],
                                                plan=case['plan']))['scope_ok'])
                    continue
                with self.assertRaises(contract.V3ContractError) as error:
                    contract.validate_plan_capabilities(case['plan'], valid['capability_surface'])
                self.assertEqual(error.exception.code, case['expected_error'])
                if case['expected_error'] == 'v3_plan_midi_pitch_unavailable':
                    details = error.exception.repair_details
                    self.assertEqual(details['command_index'], 6 if case['name'].startswith('partial') else 9)
                    self.assertEqual(details['command_type'], 'midi.create_clip')
                    self.assertEqual(details['effective_instrument_id'], 'free-piano')
                    self.assertEqual(details['rejected_pitches'], [36, 38] if case['name'].startswith('partial') else [36])
                    self.assertEqual(details['playable_pitch_ranges'], [{'low': 40, 'high': 84}])
                else:
                    capacity = case['expected_error'] == 'v3_plan_row_capacity_exceeded'
                    failing = 2 if capacity else 5
                    prefix = copy.deepcopy(case['plan'])
                    prefix['commands'] = prefix['commands'][:failing]
                    contract.validate_plan_capabilities(prefix, valid['capability_surface'])
                    prefix['commands'].append(case['plan']['commands'][failing])
                    with self.assertRaises(contract.V3ContractError) as prefix_error:
                        contract.validate_plan_capabilities(prefix, valid['capability_surface'])
                    self.assertEqual(prefix_error.exception.code, case['expected_error'])
                    self.assertEqual(case['request']['core_context']['project']['row_capacity']['current_rows'], 6)
                    self.assertEqual(case['request']['core_context']['project']['row_capacity']['max_rows'], 8)
                    self.assertEqual(prefix['commands'][-1]['type'], 'row.create' if capacity else 'row.delete')

    def test_exact_pitch_repairs_preserve_every_other_field(self):
        for fixture in cases():
            if fixture['expected_error'] != 'v3_plan_midi_pitch_unavailable':
                continue
            valid = request(fixture)
            body = contract.build_provider_request(valid, model=original.MODEL, reasoning_effort='low')
            before = copy.deepcopy(fixture['plan'])
            prepared = repair.prepare(valid, repair.plan_payload(before), body)
            self.assertEqual(len(prepared.violations), 4)
            corrected = repair.reconstruct(prepared, mocked_patch(prepared))
            expected = copy.deepcopy(before)
            for violation in prepared.violations:
                expected['commands'][violation['command_index']]['arguments']['notes'][violation['note_index']]['pitch'] = 48
            self.assertEqual(corrected, expected)
            self.assertEqual(fixture['plan'], before)
            contract.validate_plan_capabilities(corrected, valid['capability_surface'])

    def test_observed_pitch_failures_use_one_shared_deadline_repair(self):
        helper = integration.PitchRepairIntegrationTests()
        for fixture in cases():
            if fixture['expected_error'] != 'v3_plan_midi_pitch_unavailable':
                continue
            with self.subTest(case=fixture['name']):
                response, provider, usage, log, _ = helper.invoke(body=fixture['request'], plan=fixture['plan'])
                self.assertEqual(response['statusCode'], 200)
                self.assertEqual(provider.timeout_seconds, [105, 95])
                self.assertEqual(len(provider.request_bodies), 2)
                self.assertEqual(len(usage.finalize_calls), 1)
                self.assertEqual(usage.release_calls, [])
                self.assertTrue(log['v3_pitch_repair_applied'])


if __name__ == '__main__':
    unittest.main()
