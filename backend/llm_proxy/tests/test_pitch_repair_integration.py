"""Real handler integration with raw synthetic provider plans and pitch patches."""
import copy
import json
import os
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest import mock

import test_api_responses as base
import test_api_responses_v3_rest as rest
import test_bounded_pitch_repair as fixtures
from common import v3_pitch_repair as repair
from handlers import api_responses, api_responses_v3_rest
from local_v3_bridge import _LambdaContext


class PitchRepairIntegrationTests(unittest.TestCase):
    def invoke(self, *, second=None, body=None, plan=None,
               rest_route=False, times=(100., 110., 110.), mutate_event=None):
        default_body, default_plan = fixtures.fixture()
        body = body or default_body
        plan = plan or default_plan
        if second is None:
            request, provider_body = fixtures.validated(body)
            case = repair.prepare(request, repair.plan_payload(plan), provider_body)
            second = fixtures.mocked_patch(case)
        if isinstance(second, dict):
            second = copy.deepcopy(second)
            second['usage'] = {'input_tokens': 100, 'output_tokens': 20, 'total_tokens': 120}
        provider = base._SequencedFakeProvider([repair.plan_payload(plan), second])
        helper = base.ApiResponsesTests()
        helper.setUp()
        output = StringIO()
        event = rest._rest_event(body) if rest_route else base._authed_event(
            json.dumps(body), path='/v1/llm/v3/responses')
        if mutate_event:
            mutate_event(event)
        try:
            with mock.patch.dict(os.environ, {
                'AI_V3_ENABLED': 'true', 'AI_V3_SERVER_CONTRACT_ENABLED': 'true',
                'AI_V3_SERVER_CONTRACT_V2_ENABLED': 'true', 'LLM_PROVIDER': 'openai',
                'AI_V3_TIMEOUT_SECONDS': '105', 'AI_V3_MAX_PROVIDER_TIMEOUT_SECONDS': '105',
                'AI_V3_TARGETED_PITCH_REPAIR_ENABLED': 'true',  # Cannot enable the feature.
            }), mock.patch.object(api_responses, '_load_api_key', return_value='synthetic'), \
                mock.patch.object(api_responses, 'get_provider', return_value=provider), \
                mock.patch.object(api_responses.time, 'monotonic', side_effect=times), \
                mock.patch.object(api_responses, 'capture_event') as analytics, \
                mock.patch.object(api_responses, 'capture_exception'), redirect_stdout(output):
                response = (api_responses_v3_rest.handler if rest_route else api_responses.handler)(
                    event, _LambdaContext(115))
            final_log = json.loads(output.getvalue().strip().splitlines()[-1])
            return response, provider, helper.fake_usage_repo, final_log, analytics.call_args_list
        finally:
            helper.doCleanups()

    def test_real_handler_reconstructs_patch_for_http_and_rest(self):
        for route in (False, True):
            with self.subTest(rest=route):
                response, provider, usage, log, analytics = self.invoke(rest_route=route)
                self.assertEqual(response['statusCode'], 200)
                plan = json.loads(response['body'])['plan']
                body, original = fixtures.fixture()
                for command in original['commands']:
                    for note in command['arguments']['notes'][:2]:
                        note['pitch'] = 48
                self.assertEqual(plan, original)
                self.assertEqual(provider.request_bodies[1]['tools'][0]['name'], repair.TOOL_NAME)
                self.assertEqual(provider.timeout_seconds, [105, 95])
                self.assertEqual(len(usage.finalize_calls), 1)
                self.assertEqual(usage.finalize_calls[0]['actual_tokens'], 120)
                self.assertEqual(usage.release_calls, [])
                self.assertTrue(log['v3_pitch_repair_applied'])
                self.assertEqual(log['resolved_tool'], 'submit_plan_v3')
                self.assertNotIn('v3_pitch_repair', response['body'])
                self.assertNotIn('v3_pitch_repair', str(analytics) + str(usage.log_calls))

    def test_request_fields_cannot_control_server_selected_repair(self):
        def injected(event):
            event['_local_v3_pitch_repair_enabled'] = True
            event['requestContext']['_local_v3_pitch_repair_enabled'] = True
            event['headers']['X-Targeted-Pitch-Repair'] = 'true'
        response, provider, _, log, _ = self.invoke(mutate_event=injected)
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(provider.request_bodies[1]['tools'][0]['name'], repair.TOOL_NAME)
        self.assertTrue(log['v3_pitch_repair_selected'])
        self.assertTrue(log['v3_pitch_repair_applied'])

    def test_valid_first_response_remains_one_attempt(self):
        body, plan = fixtures.fixture()
        for command in plan['commands']:
            for note in command['arguments']['notes']:
                note['pitch'] = 48
        with mock.patch.object(repair, 'prepare', side_effect=AssertionError('unnecessary repair')):
            response, provider, usage, log, _ = self.invoke(plan=plan, second={}, times=(100.,))
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(len(provider.request_bodies), 1)
        self.assertEqual(len(usage.finalize_calls), 1)
        self.assertNotIn('v3_pitch_repair_selected', log)

    def test_ineligible_pitch_dependency_uses_existing_repair_once(self):
        body, plan = fixtures.fixture()
        plan['commands'].append({'command_id': 'switch', 'type': 'row.set_instrument',
            'arguments': {'row_id': 101, 'instrument_id': 'wide'}})
        corrected = copy.deepcopy(plan)
        for command in corrected['commands'][:2]:
            for note in command['arguments']['notes']:
                note['pitch'] = 48
        response, provider, usage, log, _ = self.invoke(plan=plan,
            second=repair.plan_payload(corrected))
        self.assertEqual(response['statusCode'], 200)
        self.assertIn('dependency_unsupported', log['v3_pitch_repair_ineligible'])
        self.assertEqual(provider.request_bodies[1]['tools'][0]['name'], 'submit_plan_v3')
        self.assertEqual(len(provider.request_bodies), 2)
        self.assertEqual(len(usage.finalize_calls), 1)

    def test_invalid_refused_incomplete_and_timeout_never_get_third_attempt(self):
        cases = [fixtures.patch_payload({}), {'output': [{'type': 'refusal'}]},
                 {'status': 'incomplete', 'output': []}, TimeoutError('synthetic timeout')]
        for second in cases:
            with self.subTest(kind=type(second).__name__):
                response, provider, usage, log, _ = self.invoke(second=second)
                self.assertEqual(response['statusCode'], 504 if isinstance(second, Exception) else 502)
                self.assertEqual(len(provider.request_bodies), 2)
                self.assertEqual(len(usage.reserve_calls), 1)
                self.assertEqual(len(usage.release_calls), 1)
                self.assertEqual(usage.finalize_calls, [])
                self.assertNotIn('plan', json.loads(response['body']))
                self.assertFalse(log.get('semantic_repair_succeeded'))

    def test_analysis_time_consumes_shared_deadline(self):
        response, provider, usage, log, _ = self.invoke(times=(100., 200., 206.))
        self.assertEqual(response['statusCode'], 502)
        self.assertEqual(len(provider.request_bodies), 1)
        self.assertTrue(log['semantic_repair_skipped_deadline'])
        self.assertEqual(len(usage.release_calls), 1)

    def test_frozen_contract_3_does_not_use_pitch_repair(self):
        body = base.ApiResponsesTests()._v3_context_body(request_contract='mixroom_v3_context_v1')
        plan = base.ApiResponsesTests()._v3_respond_plan()
        results = []
        with mock.patch.object(repair, 'prepare', side_effect=AssertionError('legacy must not use repair')):
            response, provider, _, log, _ = self.invoke(body=body,
                plan=plan, second={}, times=(100.,))
            self.assertEqual(response['statusCode'], 200)
            self.assertFalse(any(key.startswith('v3_pitch_repair') for key in log))
            results.append((json.loads(response['body']), provider.request_bodies))
        self.assertEqual(len(results), 1)


if __name__ == '__main__':
    unittest.main()
