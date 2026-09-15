"""Offline cross-client budget fixtures; no provider calls."""
import copy
import json
import os
from pathlib import Path
import unittest
from unittest import mock

import test_v3_server_contract as helpers
from common import v3_server_contract as contract
from common import ai_limits, v3_pitch_repair

FIXTURE = json.loads((Path(__file__).parent / 'fixtures/generated_midi_budget_v1.json').read_text())


class GeneratedMidiBudgetTests(unittest.TestCase):
    def context(self, marker=None):
        context = helpers.V3ServerContractTests()._core_context()
        if marker is not None:
            context['project']['generated_midi_policy'] = marker
        return context

    def plan(self, count, mixed=False):
        commands = []
        counts = [count] if not mixed else [count // 2, count - count // 2]
        for index, length in enumerate(counts):
            commands.append({'command_id': f'edit-{index}', 'type': 'midi.replace_notes',
                'arguments': {'clip_id': 'clip-1', 'notes': [copy.deepcopy(FIXTURE['note']) for _ in range(length)]}})
        return {'schema_version': contract.PLAN_SCHEMA_VERSION, 'outcome': 'plan',
                'user_message': 'Updated the notes.', 'commands': commands, 'question_options': []}

    def args(self, surface, refs=False):
        return dict(command_types=['midi.replace_notes'], resource_refs_enabled=refs,
                    capability_surface=surface, original_request='Replace the notes.')

    def test_shared_boundaries_and_fallback(self):
        for marker in (None, 'unknown', 512, {'notes': 512}, FIXTURE['policy']):
            surface = contract.extract_capability_surface(self.context(marker))
            limit = 512 if marker == FIXTURE['policy'] else 256
            self.assertEqual(contract.output_budget(surface).notes, limit)
            for count in FIXTURE['counts']:
                for mixed in (False, True):
                    for refs in (False, True):
                        with self.subTest(marker=marker, count=count, mixed=mixed, refs=refs):
                            payload = v3_pitch_repair.plan_payload(self.plan(count, mixed))
                            if count <= limit:
                                accepted = contract.parse_and_validate_provider_plan(payload, **self.args(surface, refs))
                                self.assertEqual(accepted, self.plan(count, mixed))
                            else:
                                with self.assertRaises(contract.V3ContractError):
                                    contract.parse_and_validate_provider_plan(payload, **self.args(surface, refs))

    def test_analysis_cannot_bypass_aggregate_limit(self):
        for marker, count in ((None, 257), (FIXTURE['policy'], 513)):
            surface = contract.extract_capability_surface(self.context(marker))
            with self.assertRaisesRegex(contract.V3ContractError, 'shared generated'):
                contract.validate_plan_capabilities(self.plan(count, True), surface, _pitch_violations=[])

    def test_mixed_commands_generated_references_and_ordered_instrument(self):
        surface = contract.extract_capability_surface(self.context(FIXTURE['policy']))
        notes = lambda count: [copy.deepcopy(FIXTURE['note']) for _ in range(count)]
        plan = self.plan(1)
        plan['commands'] = [
            {'command_id': 'switch', 'type': 'row.set_instrument',
             'arguments': {'row_id': 101, 'instrument_id': 'free-piano'}},
            {'command_id': 'create', 'type': 'midi.create_clip', 'arguments': {
                'destination': {'row_id': 101}, 'start_beat': 0, 'length_beats': 4, 'notes': notes(170)}},
            {'command_id': 'replace', 'type': 'midi.replace_notes', 'arguments': {
                'clip_ref': {'command_id': 'create', 'output': 'midi_clip'}, 'notes': notes(171)}},
            {'command_id': 'append', 'type': 'midi.append_notes', 'arguments': {
                'clip_ref': {'command_id': 'create', 'output': 'midi_clip'}, 'notes': notes(171)}},
        ]
        args = self.args(surface, True)
        args['command_types'] = [command['type'] for command in plan['commands']]
        self.assertEqual(contract.parse_and_validate_provider_plan(
            v3_pitch_repair.plan_payload(plan), **args), plan)
        plan['commands'][-1]['arguments']['notes'].append(copy.deepcopy(FIXTURE['note']))
        with self.assertRaisesRegex(contract.V3ContractError, 'shared generated'):
            contract.parse_and_validate_provider_plan(v3_pitch_repair.plan_payload(plan), **args)

    def test_512_note_pitch_reconstruction_and_remaining_safety(self):
        surface = contract.extract_capability_surface(self.context(FIXTURE['policy']))
        request = dict(supported_command_types=['midi.replace_notes'], resource_refs_enabled=False,
            capability_surface=surface, original_request='Replace notes.', conversation=[], core_context=self.context(FIXTURE['policy']))
        body = contract.build_provider_request(request, model='test', reasoning_effort='low')
        plan = self.plan(512)
        plan['commands'][0]['arguments']['notes'][0]['pitch'] = 36
        case = v3_pitch_repair.prepare(request, v3_pitch_repair.plan_payload(plan), body)
        self.assertEqual(case.body['max_output_tokens'], 16384)
        patch = {'status': 'completed', 'output': [{'type': 'function_call',
            'name': v3_pitch_repair.TOOL_NAME, 'arguments': '{"c0_n0":60}'}]}
        self.assertEqual(v3_pitch_repair.reconstruct(case, patch), self.plan(512))
        patch['output'][0]['arguments'] = '{"c0_n0":36}'
        with self.assertRaises(v3_pitch_repair.RepairRejected):
            v3_pitch_repair.reconstruct(case, patch)
        plan['commands'][0]['arguments']['notes'][1]['start_beat'] = 100
        with self.assertRaises(v3_pitch_repair.RepairRejected):
            v3_pitch_repair.prepare(request, v3_pitch_repair.plan_payload(plan), body)

    def test_budget_fingerprint_is_capability_specific(self):
        values = []
        for marker in (None, 'unknown', FIXTURE['policy']):
            surface = contract.extract_capability_surface(self.context(marker))
            values.append(contract.contract_fingerprint(command_types=['midi.replace_notes'],
                resource_refs_enabled=False, capability_surface=surface))
        self.assertEqual(values[0], values[1])
        self.assertNotEqual(values[0], values[2])

    def test_budgets_and_instruction_both_tool_variants(self):
        for marker in (None, FIXTURE['policy']):
            surface = contract.extract_capability_surface(self.context(marker))
            budget = contract.output_budget(surface)
            for refs in (False, True):
                request = dict(supported_command_types=['midi.replace_notes'], resource_refs_enabled=refs,
                    capability_surface=surface, original_request='Replace notes.', conversation=[], core_context=self.context(marker))
                body = contract.build_provider_request(request, model='test', reasoning_effort='low')
                self.assertEqual(body['max_output_tokens'], budget.output_tokens)
                self.assertIn(f'at most {budget.notes} explicit notes', body['instructions'])
                limits = []
                def walk(node):
                    if isinstance(node, dict):
                        notes = node.get('properties', {}).get('notes')
                        if isinstance(notes, dict):
                            limits.append(notes['maxItems'])
                        for value in node.values(): walk(value)
                    elif isinstance(node, list):
                        for value in node: walk(value)
                walk(body['tools'])
                self.assertTrue(limits)
                self.assertEqual(set(limits), {budget.notes})
                capped = contract.build_provider_request(request, model='test', reasoning_effort='low', max_output_tokens=99999)
                self.assertEqual(capped['max_output_tokens'], budget.output_tokens)

    def test_plan_byte_ceiling_checked_before_schema(self):
        for marker in (None, FIXTURE['policy']):
            surface = contract.extract_capability_surface(self.context(marker))
            limit = contract.output_budget(surface).plan_bytes
            plan = self.plan(1)
            plan['padding'] = ''
            length = len(contract._canonical_json(plan).encode())
            plan['padding'] = 'x' * (limit - length)
            with mock.patch.object(contract, '_validate_json_schema'), mock.patch.object(contract, '_validate_user_visible_text'):
                contract.parse_provider_plan_structure(v3_pitch_repair.plan_payload(plan), **self.args(surface))
                plan['padding'] += 'x'
                with self.assertRaisesRegex(contract.V3ContractError, 'output budget'):
                    contract.parse_provider_plan_structure(v3_pitch_repair.plan_payload(plan), **self.args(surface))

    def test_explicit_operational_cap_is_preserved(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            body = {'max_output_tokens': 16384}
            ai_limits.apply_server_output_token_cap(body, default_limit=16384)
            self.assertEqual(body['max_output_tokens'], 16384)
        with mock.patch.dict(os.environ, {'LLM_MAX_OUTPUT_TOKENS': '8192'}):
            body = {'max_output_tokens': 16384}
            ai_limits.apply_server_output_token_cap(body, default_limit=16384)
            self.assertEqual(body['max_output_tokens'], 8192)
