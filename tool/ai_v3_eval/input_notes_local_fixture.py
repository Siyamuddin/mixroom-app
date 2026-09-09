"""Offline native continuation fixture; never loads credentials or a live provider."""
import argparse
import itertools
import json
import sys

import local_v3_bridge as bridge
from common import v3_pitch_repair


class InputNotesProvider:
    name = 'local-input-notes-fixture'
    sequence = itertools.count()

    def __init__(self, *, scenario, delay_ms):
        self.case = next(self.sequence)
        assert self.case < 3, 'Offline fixture exhausted'
        self.attempt_count = 0

    def forward_request(self, *, api_key, request_body, timeout_seconds):
        assert api_key == 'local-test-key'
        self.attempt_count += 1
        assert self.attempt_count == 1
        content = request_body['messages'][0]['content']
        context = json.loads(next(item['text'].split('\n', 1)[1] for item in content
            if item.get('text', '').startswith('CORE_CONTEXT_V3_JSON:\n')))
        row = context['rows'][0]
        print(json.dumps({'fixture_row_kind': row.get('lane_kind'),
                          'fixture_instrument': row.get('instrument_id')}),
              file=sys.stderr, flush=True)
        expected = [dict(pitch=48 + i % 4 * 4, start_beat=(i // 4) * 0.125,
                         length_beats=0.125, velocity=0.75) for i in range(512)]
        assert len(context['clips']) == self.case
        for clip in context['clips']:
            assert clip['midi_notes'] == expected, 'Input notes omitted or altered'
        if self.case < 2:
            command = dict(command_id='create', type='midi.create_clip', arguments=dict(
                destination={'row_id': row['row_id']}, start_beat=4 + self.case * 16,
                length_beats=16, notes=expected))
        else:
            command = dict(command_id='rename', type='row.rename', arguments=dict(
                row_id=row['row_id'], new_name='Complete 1024-note project'))
        payload = v3_pitch_repair.plan_payload(dict(schema_version='plan_v3_prototype_2',
            outcome='plan', user_message='Applied the requested deterministic edit.',
            commands=[command], question_options=[]))
        print(json.dumps({'input_notes_verified': self.case * 512,
                          'fixture_request': self.case + 1}), file=sys.stderr, flush=True)
        payload['usage'] = {'input_tokens': 100, 'output_tokens': 20, 'total_tokens': 120}
        return {'statusCode': 200, 'body': json.dumps(payload)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8771)
    args = parser.parse_args()
    bridge.DeterministicProvider = InputNotesProvider
    server = bridge.create_server(port=args.port, transport_mode='long')
    print('Offline input-note fixture ready', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
