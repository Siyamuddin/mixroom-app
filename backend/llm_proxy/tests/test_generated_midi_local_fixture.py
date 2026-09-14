"""Real local REST handler acceptance, without a model or app process."""
import itertools
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

import test_api_responses as helpers

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tool/ai_v3_eval'))
import generated_midi_local_fixture as fixture


class GeneratedMidiLocalFixtureTests(unittest.TestCase):
    def test_create_512_and_reject_513_through_rest_handler(self):
        body = helpers.ApiResponsesTests()._v3_midi_repair_body()
        body['supported_command_types'] = ['midi.create_clip', 'midi.replace_notes']
        context = body['core_context']
        instrument = 'sfz.guitar.clean_electric'
        context['project'].update(generated_midi_policy='notes_512_v1', bpm=120)
        context['rows'][0]['instrument_id'] = instrument
        context['clips'] = []
        context['instruments'] = [instrument]
        context['instrument_catalog'] = [{'instrument_id': instrument, 'name': 'Electric Guitar',
            'playable_pitch_ranges': [{'low': 40, 'high': 86}]}]
        backend = fixture.bridge.LocalBackend(scenario='success', delay_ms=0,
            provider_timeout_seconds=105, transport_mode='long')
        with mock.patch.object(fixture.GeneratedMidiFixtureProvider, 'sequence', itertools.count()), \
            mock.patch.object(fixture.bridge, 'DeterministicProvider', fixture.GeneratedMidiFixtureProvider), \
            mock.patch.dict(os.environ, {'LLM_MAX_OUTPUT_TOKENS': ''}):
            created, measurement = backend.invoke(json.dumps(body), request_number=1)
            self.assertEqual(created['statusCode'], 200)
            notes = json.loads(created['body'])['plan']['commands'][0]['arguments']['notes']
            self.assertEqual(len(notes), 512)
            self.assertEqual(measurement['provider_attempt_count'], 1)
            context['clips'] = [{'clip_id': 'created', 'row_id': 101, 'kind': 'midi',
                'instrument_id': instrument, 'length_beats': 16, 'midi_notes': notes}]
            rejected, measurement = backend.invoke(json.dumps(body), request_number=2)
            self.assertEqual(rejected['statusCode'], 502)
            self.assertEqual(measurement['provider_attempt_count'], 1)
            self.assertEqual(backend.usage.finalize_count, 1)
            self.assertEqual(backend.usage.release_count, 1)
