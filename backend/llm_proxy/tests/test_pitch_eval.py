import sys
import copy
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tool/ai_v3_eval'))
from evaluate_pitch import prepare, instruments_match
from pitch_candidate import candidate
from row_rebuild_revision import historical_instructions
from evaluate_pitch_presentation import prepare as prepare_presentation, add_summary
from common import v3_server_contract as contract


class PitchEvalTests(unittest.TestCase):
    def test_presentation_candidate_only_adds_derived_data_beside_request(self):
        for i in range(5):
            valid, before, after = prepare_presentation(i)
            restored = copy.deepcopy(after)
            block = restored['messages'][0]['content'].pop(-2)
            self.assertEqual(before, restored)
            summary = json.loads(block['text'].split('\n', 1)[1])
            self.assertEqual(summary['inclusive_pitch_intervals_by_instrument'], {
                item.instrument_id: [[r.low, r.high] for r in item.playable_pitch_ranges]
                for item in valid['capability_surface'].instruments})
            self.assertEqual(after, add_summary(before, valid['capability_surface']))
            self.assertEqual(len(valid['capability_surface'].instruments), 135)
            if i == 3:
                drums = valid['capability_surface'].instruments[0]
                self.assertTrue(drums.can_play(38))
                self.assertFalse(drums.can_play(39))
                self.assertTrue(drums.can_play(42))

    def test_candidate_is_eval_only_and_changes_only_instructions(self):
        for i in range(5):
            valid, before, after = prepare(i)
            self.assertEqual({k:v for k,v in before.items() if k != 'instructions'},
                             {k:v for k,v in after.items() if k != 'instructions'})
            for refs in (False, True):
                request = dict(valid, resource_refs_enabled=refs)
                body = contract.build_provider_request(request, model='gpt-5.6-luna',
                    reasoning_effort='low', max_output_tokens=8192)
                historical = historical_instructions(body['instructions'])
                self.assertNotEqual(candidate(historical), historical)

    def test_instrument_grader_does_not_accept_omitted_switch(self):
        create = {'command_id': 'create', 'type': 'midi.create_clip',
                  'arguments': {'destination': {'row_id': 101}}}
        self.assertFalse(instruments_match([create], 4))
        switch = {'command_id': 'switch', 'type': 'row.set_instrument',
                  'arguments': {'row_id': 101, 'instrument_id': 'sfz.guitar.clean_electric'}}
        self.assertTrue(instruments_match([switch, create], 4))

    def test_instrument_grader_resolves_generated_row_lane(self):
        row = {'command_id': 'row', 'type': 'row.create', 'arguments': {
            'lane': {'kind': 'midi', 'instrument_id': 'synthetic-remapped-drums'}}}
        create = {'command_id': 'create', 'type': 'midi.create_clip', 'arguments': {
            'destination': {'row_ref': {'command_id': 'row', 'output': 'row'}}}}
        self.assertTrue(instruments_match([row, create], 3))
        row['arguments']['lane']['instrument_id'] = 'other-instrument'
        self.assertFalse(instruments_match([row, create], 3))
