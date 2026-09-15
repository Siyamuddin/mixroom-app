import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tool/ai_v3_eval'))
import evaluate_row_rebuild as evaluation
from score_row_rebuild import scope
from common.v3_pitch_repair import plan_payload


class RowRebuildEvaluationTests(unittest.TestCase):
    def test_scope_does_not_turn_invalid_order_into_success(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        case = fixture['cases'][0]
        score = scope(dict(case='jazz_restart', context=case['context'], plan=case['plan']))
        self.assertTrue(score['last_row_violation'])
        self.assertTrue(score['scope_ok'])
        # Scope and executability deliberately remain separate gates.

    def test_protected_content_is_not_certified_after_an_edit(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        case = copy.deepcopy(fixture['cases'][0])
        score = scope(dict(case='partial_rebuild', context=case['context'], plan=case['plan']))
        self.assertFalse(score['protected_content_ok'])
        self.assertFalse(score['scope_ok'])

    def test_unknown_scoring_operation_requires_review(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        case = copy.deepcopy(next(c for c in fixture['cases'] if c['backend_error'] is None))
        case['plan']['commands'].append(dict(type='project.set_tempo', arguments={'bpm': 100}))
        score = scope(dict(case='jazz_restart', context=case['context'], plan=case['plan']))
        self.assertTrue(score['scope_review_required'])

    def test_position_anchor_does_not_modify_protected_row(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        case = copy.deepcopy(fixture['cases'][0])
        case['plan']['commands'] = [dict(command_id='new', type='row.create',
            arguments={'lane': {'kind': 'midi', 'instrument_id': 'free-piano'},
                       'position': {'kind': 'after', 'row_id': 105}})]
        result = scope(dict(case='partial_rebuild', context=case['context'], plan=case['plan']))
        self.assertTrue(result['protected_content_ok'])

    def test_fixed_balanced_interleaved_schedule(self):
        jobs = evaluation.jobs()
        self.assertEqual(len(jobs), 40)
        self.assertEqual(len(set(jobs)), 40)
        for index in range(5):
            for variant in ('baseline', 'candidate'):
                self.assertEqual(sum(i == index and v == variant for i, _, v in jobs), 4)
        for offset in range(0, 40, 2):
            self.assertEqual(jobs[offset][:2], jobs[offset + 1][:2])
            self.assertNotEqual(jobs[offset][2], jobs[offset + 1][2])

    def test_requests_are_deterministic_and_only_instructions_differ(self):
        for index in range(5):
            body, valid, baseline, candidate = evaluation.prepare(index)
            self.assertEqual(evaluation.canonical(baseline), evaluation.canonical(evaluation.prepare(index)[2]))
            self.assertEqual(baseline['max_output_tokens'], 16384)
            self.assertEqual(baseline['model'], 'gpt-5.6-luna')
            changed = copy.deepcopy(candidate)
            changed['instructions'] = baseline['instructions']
            self.assertEqual(changed, baseline)
            self.assertEqual(len(valid['supported_command_types']), 54)
            self.assertEqual(len(body['core_context']['rows']), 1 if index == 3 else 6)

    def test_exact_prompt_and_full_capacity_case(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        self.assertEqual(evaluation.prepare(0)[0]['original_request'], fixture['original_request'])
        self.assertFalse(evaluation.prepare(2)[0]['core_context']['project']['row_capacity']['can_create'])

    def test_synthetic_bad_order_is_not_first_pass_success(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        valid = evaluation.prepare(1)[1]
        result = evaluation.assess(plan_payload(fixture['cases'][0]['plan']), valid)
        self.assertFalse(result['backend_valid'])
        self.assertEqual(result['error'], 'v3_plan_capability_invalid')
        self.assertTrue(result['review_required'])
        self.assertIn('plan', result)

    def test_success_still_requires_scope_and_language_review(self):
        fixture = json.loads(evaluation.FIXTURE.read_text())
        case = next(c for c in fixture['cases'] if c['backend_error'] is None)
        result = evaluation.assess(plan_payload(case['plan']), evaluation.prepare(1)[1])
        self.assertTrue(result['backend_valid'])
        self.assertTrue(result['review_required'])
        self.assertNotIn('success', result)

    def test_failures_never_invoke_repair_or_retry(self):
        class FakeProvider:
            calls = 0

            def forward_request(self, **kwargs):
                self.calls += 1
                assert kwargs['timeout_seconds'] == 105
                raise TimeoutError('synthetic')

        provider = FakeProvider()
        result = evaluation.execute((0, 0, 'baseline'), 'synthetic', provider)
        self.assertEqual(provider.calls, 1)
        self.assertEqual(result['error'], 'TimeoutError')
        self.assertEqual(result['provider_attempts'], 1)


if __name__ == '__main__':
    unittest.main()
