import copy
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tool/ai_v3_eval'))
import compare_request_weight as comparison

class RequestWeightComparisonTests(unittest.TestCase):
    def test_candidate_expansion_is_exact_and_deterministic(self):
        first = comparison.prepare()
        second = comparison.prepare()
        self.assertEqual(first[1:], second[1:])
        baseline, candidate = first[1:]
        original = copy.deepcopy(baseline)
        self.assertEqual(comparison.expand(candidate['tools'][0]['parameters']),
                         baseline['tools'][0]['parameters'])
        candidate['tools'][0]['parameters'] = comparison.expand(candidate['tools'][0]['parameters'])
        self.assertEqual(candidate, baseline)
        self.assertEqual(baseline, original)

    def test_enum_values_order_and_descriptions_are_not_lost(self):
        enum = {'type': 'string', 'enum': ['synthetic-' + str(i) for i in range(40)], 'description': 'Fixed choices'}
        schema = {'type': 'object', 'properties': {'a': enum, 'b': copy.deepcopy(enum)},
                  'required': ['a', 'b'], 'additionalProperties': False}
        changed = comparison.deduplicate(schema)
        self.assertIn('$defs', changed)
        self.assertEqual(comparison.expand(changed), schema)
        self.assertEqual(comparison.deduplicate({'type': 'integer'}), {'type': 'integer'})
        with self.assertRaises(AssertionError): comparison.deduplicate({'$ref': '#/unsupported'})

    def test_scope_requires_every_clip_and_no_unrelated_edits(self):
        request, _, _ = comparison.prepare()
        plan = {'commands': [{'type': 'midi.replace_notes', 'arguments': {
            'clip_id': c['clip_id'], 'notes': [{'pitch': 60, 'start_beat': 0, 'length_beats': 1, 'velocity': 0.8}]}}
            for c in request['core_context']['clips']]}
        self.assertTrue(comparison.scope_check(plan, request))
        for changed in (plan['commands'][:-1], plan['commands'] + plan['commands'][:1],
                        plan['commands'] + [{'type': 'row.set_instrument'}]):
            self.assertFalse(comparison.scope_check({'commands': changed}, request))

    def test_timeout_is_one_attempt_without_repair(self):
        request, body, _ = comparison.prepare()
        with patch.object(comparison, 'get_provider') as provider:
            provider.return_value.forward_request.side_effect = TimeoutError()
            result = comparison.run_trial(request, body, 'synthetic-secret', None)
            self.assertEqual(result['error'], 'timeout')
            self.assertEqual(provider.return_value.forward_request.call_count, 1)
            self.assertNotIn('synthetic-secret', json.dumps(result))

    def test_client_rejection_is_reported_not_counted_as_success(self):
        request, body, _ = comparison.prepare()
        plan = {'schema_version': comparison.contract.PLAN_SCHEMA_VERSION, 'outcome': 'plan',
            'user_message': 'SECRET_REPLY', 'question_options': [], 'commands': [
                {'command_id': f'replace-{i}', 'type': 'midi.replace_notes', 'arguments': {
                    'clip_id': c['clip_id'], 'notes': [{'pitch': 60 if i != 1 else 38,
                        'start_beat': 0, 'length_beats': 1, 'velocity': 0.8}]}}
                for i, c in enumerate(request['core_context']['clips'])]}
        payload = {'status': 'completed', 'output': [{'type': 'function_call', 'name': 'submit_plan_v3',
            'arguments': json.dumps(plan)}]}
        class Checker:
            stdin = io.StringIO()
            stdout = io.StringIO('{"valid":false,"error":"v3_generated_midi_limit"}\n')
        with patch.object(comparison, 'get_provider') as provider:
            provider.return_value.forward_request.return_value = {'statusCode': 200, 'body': json.dumps(payload)}
            result = comparison.run_trial(request, body, 'synthetic-secret', Checker())
        self.assertTrue(result['backend_valid'])
        self.assertFalse(result['executable_contract_success'])
        self.assertEqual(result['client_error'], 'v3_generated_midi_limit')
        self.assertNotIn('SECRET_REPLY', json.dumps(result))

if __name__ == '__main__': unittest.main()
