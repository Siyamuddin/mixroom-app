"""Four-request, fake-provider fixture for native pitch-repair integration.

Only test data: create two guitar sections, replace, append, then invalid patch.
No model calls. The real local handler decides eligibility and reconstructs plans.
"""
import argparse
import itertools
import json

import local_v3_bridge as bridge
from common import v3_pitch_repair as repair


class PitchFixtureProvider:
    name = 'local-pitch-fixture'
    sequence = itertools.count()

    def __init__(self, *, scenario, delay_ms):
        self.case = next(self.sequence)
        if self.case > 3:
            raise RuntimeError('The four-request offline fixture is exhausted.')
        self.attempt_count = 0

    def forward_request(self, *, api_key, request_body, timeout_seconds):
        assert api_key == 'local-test-key'
        self.attempt_count += 1
        assert self.attempt_count <= 2
        if self.attempt_count == 1:
            content = request_body['messages'][0]['content']
            context = json.loads(next(item['text'].split('\n', 1)[1] for item in content
                if item.get('text', '').startswith('CORE_CONTEXT_V3_JSON:\n')))
            row = next(row for row in context['rows']
                if row.get('instrument_id') == 'sfz.guitar.clean_electric')
            notes = [dict(pitch=35 if i == 0 else (47, 52, 55, 59)[self.case], start_beat=i * 4,
                          length_beats=4, velocity=0.8) for i in range(8)]
            if self.case == 0:
                commands = [dict(command_id=f'section-{i}', type='midi.create_clip',
                    arguments=dict(destination={'row_id': row['row_id']},
                        start_beat=i * 32, length_beats=32, notes=notes)) for i in range(2)]
            else:
                clip = next(clip for clip in context['clips'] if clip['row_id'] == row['row_id'])
                commands = [dict(command_id='notes', type=(
                    'midi.append_notes' if self.case == 2 else 'midi.replace_notes'),
                    arguments=dict(clip_id=clip['clip_id'], notes=notes))]
            self.initial = repair.plan_payload(dict(schema_version='plan_v3_prototype_2',
                outcome='plan', user_message='Updated the guitar arrangement.',
                commands=commands, question_options=[]))
            payload = self.initial
        else:
            if request_body['tools'][0]['name'] == repair.TOOL_NAME:
                # Explicit mocked model output, never runtime pitch clamping.
                patch = {key: 0 if self.case == 3 else 48
                         for key in request_body['tools'][0]['parameters']['properties']}
                payload = {'status': 'completed', 'output': [{'type': 'function_call',
                    'name': repair.TOOL_NAME, 'arguments': json.dumps(patch)}]}
            else:
                payload = self.initial
        payload['usage'] = {'input_tokens': 100, 'output_tokens': 20, 'total_tokens': 120}
        return {'statusCode': 200, 'body': json.dumps(payload)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8768)
    parser.add_argument('--targeted-pitch-repair', action='store_true')
    args = parser.parse_args()
    bridge.DeterministicProvider = PitchFixtureProvider
    server = bridge.create_server(port=args.port, transport_mode='long',
        targeted_pitch_repair=args.targeted_pitch_repair)
    print(json.dumps({'message': 'Pitch fixture bridge ready', 'url': f'http://127.0.0.1:{server.server_port}',
                      'external_calls': False}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
