"""Two-request offline native acceptance fixture: create 512, reject 513.

Uses the actual REST adapter/handler with a fake provider and in-memory usage.
No credentials, model calls, or production data. This process never imports a
live bridge. Restart the fixture for each native test run.
"""
import argparse
import itertools
import json

import local_v3_bridge as bridge
from common import v3_pitch_repair


class GeneratedMidiFixtureProvider:
    name = 'local-generated-midi-fixture'
    sequence = itertools.count()

    def __init__(self, *, scenario, delay_ms):
        self.case = next(self.sequence)
        if self.case > 1:
            raise RuntimeError('The two-request offline fixture is exhausted.')
        self.attempt_count = 0

    def forward_request(self, *, api_key, request_body, timeout_seconds):
        assert api_key == 'local-test-key'
        assert request_body['max_output_tokens'] == 16384, 'Output ceiling is still capped.'
        assert timeout_seconds <= 105
        self.attempt_count += 1
        assert self.attempt_count == 1, 'Unexpected repair attempt.'
        content = request_body['messages'][0]['content']
        context = json.loads(next(item['text'].split('\n', 1)[1] for item in content
            if item.get('text', '').startswith('CORE_CONTEXT_V3_JSON:\n')))
        assert context['project']['generated_midi_policy'] == 'notes_512_v1'
        row = next(row for row in context['rows']
            if row.get('instrument_id') == 'sfz.guitar.clean_electric')
        # Four-note chords over 128 eighth-beat positions. Exact binary fractions
        # avoid introducing a separate floating-point boundary test here.
        notes = [dict(pitch=48 + i % 4 * 4, start_beat=(i // 4) * 0.125,
                      length_beats=0.125, velocity=0.75) for i in range(512)]
        if self.case:
            notes.append(dict(notes[0]))
        if self.case == 0:
            command = dict(command_id='create-512', type='midi.create_clip',
                arguments=dict(destination={'row_id': row['row_id']},
                    start_beat=4, length_beats=16, notes=notes))
        else:
            clip = next(clip for clip in context['clips'] if clip['row_id'] == row['row_id'])
            command = dict(command_id='reject-513', type='midi.replace_notes',
                arguments=dict(clip_id=clip['clip_id'], notes=notes))
        payload = v3_pitch_repair.plan_payload(dict(schema_version='plan_v3_prototype_2',
            outcome='plan', user_message='Created the deterministic guitar arrangement.',
            commands=[command], question_options=[]))
        payload['usage'] = {'input_tokens': 100, 'output_tokens': 20, 'total_tokens': 120}
        return {'statusCode': 200, 'body': json.dumps(payload)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8769)
    args = parser.parse_args()
    bridge.DeterministicProvider = GeneratedMidiFixtureProvider
    server = bridge.create_server(port=args.port, transport_mode='long')
    print(json.dumps({'message': 'Generated MIDI fixture ready',
        'url': f'http://127.0.0.1:{server.server_port}', 'external_calls': False}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
