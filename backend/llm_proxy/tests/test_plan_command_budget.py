"""Offline command policy compatibility; no provider calls."""
import copy
import json
from pathlib import Path
import unittest

import test_v3_server_contract as helpers
import test_pitch_repair_integration as integration
from common import v3_server_contract as contract, v3_pitch_repair

FIXTURE = json.loads((Path(__file__).parent / 'fixtures/plan_command_budget_v1.json').read_text())


def plan(count):
    return {'schema_version': contract.PLAN_SCHEMA_VERSION, 'outcome': 'plan',
        'user_message': 'Renamed the row.', 'question_options': [], 'commands': [
            {'command_id': f'edit-{i}', 'type': 'row.rename',
             'arguments': {'row_id': FIXTURE['row_id'], 'new_name': FIXTURE['name_prefix'] + str(i)}}
            for i in range(count)]}


class PlanCommandBudgetTests(unittest.TestCase):
    def request(self, marker=None, notes=True):
        context = helpers.V3ServerContractTests()._core_context()
        if marker is not None:
            context['project']['plan_command_policy'] = marker
        if notes:
            context['project']['generated_midi_policy'] = contract.GENERATED_MIDI_POLICY
        body = {'request_contract': 'mixroom_v3_context_v2',
            'plan_schema_version': contract.PLAN_SCHEMA_VERSION,
            'original_request': 'Rename the row.', 'conversation': [],
            'core_context': context, 'resource_refs_enabled': True,
            'supported_command_types': ['row.rename', 'midi.replace_notes']}
        return body, contract.validate_context_request(body, raw_body_bytes=len(json.dumps(body).encode()))

    def test_shared_boundaries_and_old_512_note_clients(self):
        for marker in (None, 'unknown', 32, {'max': 32}, FIXTURE['policy']):
            _, request = self.request(marker)
            surface = request['capability_surface']
            limit = 32 if marker == FIXTURE['policy'] else 16
            self.assertEqual(contract.command_limit(surface), limit)
            for count in FIXTURE['counts']:
                for refs in (False, True):
                    args = dict(command_types=['row.rename'], resource_refs_enabled=refs,
                                capability_surface=surface)
                    with self.subTest(marker=marker, count=count, refs=refs):
                        if count <= limit:
                            self.assertEqual(contract.parse_and_validate_provider_plan(
                                v3_pitch_repair.plan_payload(plan(count)), **args), plan(count))
                        else:
                            with self.assertRaises(contract.V3ContractError):
                                contract.parse_and_validate_provider_plan(v3_pitch_repair.plan_payload(plan(count)), **args)
                            with self.assertRaises(contract.V3ContractError):
                                contract.validate_plan_capabilities(plan(count), surface, _pitch_violations=[])

    def test_only_command_schema_and_fingerprint_change(self):
        for notes in (False, True):
            _, old = self.request(notes=notes)
            _, new = self.request(FIXTURE['policy'], notes=notes)
            _, unknown = self.request('unknown', notes=notes)
            for refs in (False, True):
                def tool(req):
                    return contract.build_submit_plan_tool(command_types=req['supported_command_types'],
                        resource_refs_enabled=refs, capability_surface=req['capability_surface'])
                a, b = tool(old), tool(new)
                self.assertEqual(a, tool(unknown))
                self.assertEqual(b['parameters']['properties']['commands']['maxItems'], 32)
                b['parameters']['properties']['commands']['maxItems'] = 16
                self.assertEqual(a, b)
                def fingerprint(req):
                    return contract.contract_fingerprint(command_types=req['supported_command_types'],
                        resource_refs_enabled=refs, capability_surface=req['capability_surface'])
                self.assertEqual(fingerprint(old), fingerprint(unknown))
                self.assertNotEqual(fingerprint(old), fingerprint(new))
            self.assertEqual(contract.output_budget(old['capability_surface']), contract.output_budget(new['capability_surface']))
            before = contract.build_provider_request(old, model='test', reasoning_effort='low')
            after = contract.build_provider_request(new, model='test', reasoning_effort='low')
            for key in ('instructions', 'model', 'reasoning', 'max_output_tokens', 'tool_choice', 'parallel_tool_calls'):
                self.assertEqual(before[key], after[key])

    def test_handler_success_and_rejection_settle_without_retries(self):
        for marker, count, accepted in ((None, 16, True), (None, 17, False),
                                       (FIXTURE['policy'], 32, True), (FIXTURE['policy'], 33, False)):
            body, _ = self.request(marker)
            response, provider, usage, _, _ = integration.PitchRepairIntegrationTests().invoke(
                body=body, plan=plan(count), second={}, times=(100.,))
            self.assertEqual(response['statusCode'], 200 if accepted else 502)
            self.assertEqual(len(provider.request_bodies), 1)
            self.assertEqual(len(usage.finalize_calls), int(accepted))
            self.assertEqual(len(usage.release_calls), int(not accepted))
            self.assertEqual('plan' in json.loads(response['body']), accepted)

    def test_existing_pitch_repair_preserves_32_commands(self):
        raw_request, request = self.request(FIXTURE['policy'])
        rejected = plan(31)
        rejected['commands'].append({'command_id': 'notes', 'type': 'midi.replace_notes',
            'arguments': {'clip_id': 'clip-1', 'notes': [
                {'pitch': 36, 'start_beat': 0, 'length_beats': 1, 'velocity': 0.7}]}})
        body = contract.build_provider_request(request, model='test', reasoning_effort='low')
        case = v3_pitch_repair.prepare(request, v3_pitch_repair.plan_payload(rejected), body)
        patch = {'status': 'completed', 'output': [{'type': 'function_call',
            'name': v3_pitch_repair.TOOL_NAME, 'arguments': '{"c31_n0":60}'}]}
        fixed = copy.deepcopy(rejected)
        fixed['commands'][-1]['arguments']['notes'][0]['pitch'] = 60
        self.assertEqual(v3_pitch_repair.reconstruct(case, patch), fixed)
        response, provider, usage, _, _ = integration.PitchRepairIntegrationTests().invoke(
            body=raw_request, plan=rejected, second=patch,
            times=(100., 110., 110.))
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(json.loads(response['body'])['plan'], fixed)
        self.assertEqual(provider.timeout_seconds, [105, 95])
        self.assertEqual(len(usage.finalize_calls), 1)
        self.assertEqual(usage.release_calls, [])
        rejected['commands'].append(copy.deepcopy(rejected['commands'][0]))
        with self.assertRaises((v3_pitch_repair.RepairRejected, contract.V3ContractError)):
            v3_pitch_repair.prepare(request, v3_pitch_repair.plan_payload(rejected), body)

    def test_complete_rebuilds_need_18_and_24_commands(self):
        fixture = json.loads((Path(__file__).parent / 'fixtures/row_rebuild_v1.json').read_text())
        for count in (6, 8):
            context = copy.deepcopy(fixture['cases'][0]['context'])
            row = context['rows'][0]
            context['rows'] = [dict(copy.deepcopy(row), row_id=100+i) for i in range(count)]
            context['clips'] = []
            context['project']['row_capacity'] = dict(current_rows=count, max_rows=count, can_create=False)
            def command(i, kind, args):
                return dict(command_id=i, type=kind, arguments=args)
            deletes = [command(f'd{i}', 'row.delete', {'row_id': 100+i}) for i in range(count)]
            creates = [command(f'r{i}', 'row.create', {'name': f'Part {i}',
                'lane': {'kind': 'midi', 'instrument_id': 'free-piano'}, 'position': {'kind': 'end'}}) for i in range(count)]
            clips = [command(f'c{i}', 'midi.create_clip', {'destination': {
                'row_ref': {'command_id': f'r{i}', 'output': 'row'}}, 'start_beat': 0,
                'length_beats': 32, 'notes': [{'pitch': 60, 'start_beat': 0, 'length_beats': 1, 'velocity': 0.7}]}) for i in range(count)]
            rebuilt = plan(0)
            rebuilt['commands'] = deletes[:-1] + creates[:1] + deletes[-1:] + creates[1:] + clips
            for capable in (False, True):
                context['project']['plan_command_policy'] = FIXTURE['policy'] if capable else ''
                args = dict(command_types=['row.delete', 'row.create', 'midi.create_clip'],
                    resource_refs_enabled=True, capability_surface=contract.extract_capability_surface(context))
                if capable:
                    self.assertEqual(contract.parse_and_validate_provider_plan(v3_pitch_repair.plan_payload(rebuilt), **args), rebuilt)
                else:
                    with self.assertRaises(contract.V3ContractError):
                        contract.parse_and_validate_provider_plan(v3_pitch_repair.plan_payload(rebuilt), **args)
